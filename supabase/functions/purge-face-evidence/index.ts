import {createClient} from 'npm:@supabase/supabase-js@2';
import {s3ConfigFromEnv, s3Request, type S3Config} from '../_shared/s3.ts';

// Invoke daily with a dedicated secret from the scheduler. Never expose this
// secret or the service key to either app. Delete bytes through Storage API;
// deleting storage.objects rows alone leaves the private objects behind.
//
// Evidence uploaded through the S3 signer (migration 157) is destroyed here
// too, by exact version: a plain DELETE would only add a delete marker and
// keep the bytes recoverable, which retention must not. This job has its own
// key (S3_RETENTION_*), the only one allowed s3:DeleteObjectVersion. Without
// S3_ENDPOINT it behaves exactly as before.
const s3: S3Config | null = Deno.env.get('S3_ENDPOINT')
  ? s3ConfigFromEnv((k) => Deno.env.get(k), 'S3_RETENTION_') : null;

// deno-lint-ignore no-explicit-any
async function purgeS3(client: any, paths: string[]): Promise<boolean> {
  if (!s3 || paths.length === 0) return true;
  const {data, error} = await client.rpc('storage_purge_begin', {p_bucket:'face-evidence', p_paths:paths});
  if (error) return false;
  for (const a of (data ?? []) as {asset_id:string; s3_bucket:string; s3_key:string; s3_version:string|null}[]) {
    const res = await s3Request(s3, 'DELETE', a.s3_bucket, a.s3_key,
      a.s3_version ? {query:[['versionId', a.s3_version]]} : {});
    await res.body?.cancel();
    if (!res.ok && res.status !== 404) return false;
    const {error: finishError} = await client.rpc('storage_finish_delete', {p_asset_id:a.asset_id});
    if (finishError) return false;
  }
  return true;
}
Deno.serve(async (request) => {
  const secret = Deno.env.get('FACE_RETENTION_SECRET');
  if (request.method !== 'POST' || !secret || request.headers.get('x-retention-secret') !== secret) {
    return new Response('Forbidden', {status:403});
  }
  const client = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const cutoff = new Date(Date.now()-30*86400000).toISOString();
  const abandoned = new Date(Date.now()-86400000).toISOString();
  const {data, error} = await client.from('face_verification_attempts').select('id,user_id,status')
    .is('media_deleted_at',null)
    .or(`created_at.lt.${cutoff},and(status.in.(draft,superseded),expires_at.lt.${abandoned})`)
    .order('created_at').limit(100);
  if (error) return new Response('Could not read retention queue',{status:500});
  let removed=0;
  for (const row of data ?? []) {
    const prefix = `${row.user_id}/${row.id}`;
    const {error: storageError} = await client.storage.from('face-evidence')
      .remove([`${prefix}/selfie.jpg`,`${prefix}/clip.webm`,`${prefix}/clip.mp4`]);
    if (storageError) return new Response('Could not remove expired evidence',{status:500});
    if (!await purgeS3(client, [`${prefix}/selfie.jpg`,`${prefix}/clip.webm`,`${prefix}/clip.mp4`])) {
      return new Response('Could not remove expired evidence from S3',{status:500});
    }
    const {error: updateError} = await client.rpc('record_face_evidence_deleted', {p_attempt_id:row.id});
    if (updateError) return new Response('Could not record evidence deletion',{status:500});
    removed++;
  }
  const {data: orphans, error: orphanError} = await client.rpc('orphan_face_evidence');
  if (orphanError) return new Response('Could not list orphaned evidence',{status:500});
  if (orphans?.length) {
    const {error: removalError} = await client.storage.from('face-evidence')
      .remove(orphans.map((item: {name:string}) => item.name));
    if (removalError) return new Response('Could not remove orphaned evidence',{status:500});
    if (!await purgeS3(client, orphans.map((item: {name:string}) => item.name))) {
      return new Response('Could not remove orphaned evidence from S3',{status:500});
    }
  }
  return Response.json({removed, orphaned:orphans?.length ?? 0, morePossible:removed===100 || orphans?.length===100});
});
