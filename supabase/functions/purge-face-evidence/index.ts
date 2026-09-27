import {createClient} from 'npm:@supabase/supabase-js@2';

// Invoke daily with a dedicated secret from the scheduler. Never expose this
// secret or the service key to either app. Delete bytes through Storage API;
// deleting storage.objects rows alone leaves the private objects behind.
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
  }
  return Response.json({removed, orphaned:orphans?.length ?? 0, morePossible:removed===100 || orphans?.length===100});
});
