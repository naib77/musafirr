// WhatsApp Webhook Edge Function
// Handles incoming messages and webhook verification from WhatsApp Business API

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const VERIFY_TOKEN = Deno.env.get('WHATSAPP_WEBHOOK_VERIFY_TOKEN') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

interface WhatsAppMessage {
  from: string
  id: string
  timestamp: string
  type: string
  text?: { body: string }
  image?: { id: string; mime_type: string; sha256: string; caption?: string }
  location?: { latitude: number; longitude: number; name?: string; address?: string }
  document?: { id: string; filename: string; mime_type: string }
}

interface WhatsAppStatus {
  id: string
  status: string
  timestamp: string
  recipient_id: string
}

interface WebhookEntry {
  id: string
  changes: Array<{
    value: {
      messaging_product: string
      metadata: {
        display_phone_number: string
        phone_number_id: string
      }
      contacts?: Array<{
        profile: { name: string }
        wa_id: string
      }>
      messages?: WhatsAppMessage[]
      statuses?: WhatsAppStatus[]
    }
    field: string
  }>
}

interface WebhookPayload {
  object: string
  entry: WebhookEntry[]
}

serve(async (req: Request) => {
  const url = new URL(req.url)

  // Handle GET requests (webhook verification)
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')

    console.log('WhatsApp Webhook Verification Request:', { mode, token, challenge: challenge?.substring(0, 20) })

    if (mode === 'subscribe' && token === VERIFY_TOKEN) {
      console.log('Webhook verified successfully')
      return new Response(challenge, { status: 200 })
    } else {
      console.error('Webhook verification failed')
      return new Response('Verification failed', { status: 403 })
    }
  }

  // Handle POST requests (incoming messages)
  if (req.method === 'POST') {
    try {
      const payload: WebhookPayload = await req.json()
      console.log('WhatsApp Webhook received:', JSON.stringify(payload, null, 2))

      if (payload.object !== 'whatsapp_business_account') {
        return new Response('Invalid object type', { status: 400 })
      }

      // Initialize Supabase client
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

      // Process each entry
      for (const entry of payload.entry) {
        for (const change of entry.changes) {
          if (change.field !== 'messages') continue

          const value = change.value
          const phoneNumberId = value.metadata.phone_number_id

          // Process messages
          if (value.messages) {
            for (const message of value.messages) {
              await processIncomingMessage(supabase, message, value.contacts?.[0], phoneNumberId)
            }
          }

          // Process status updates
          if (value.statuses) {
            for (const status of value.statuses) {
              await processStatusUpdate(supabase, status, phoneNumberId)
            }
          }
        }
      }

      return new Response(JSON.stringify({ status: 'ok' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    } catch (error) {
      console.error('Error processing webhook:', error)
      return new Response(JSON.stringify({ error: 'Internal server error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }
  }

  return new Response('Method not allowed', { status: 405 })
})

async function processIncomingMessage(
  supabase: ReturnType<typeof createClient>,
  message: WhatsAppMessage,
  contact: { profile: { name: string }; wa_id: string } | undefined,
  phoneNumberId: string
) {
  console.log('Processing incoming WhatsApp message:', {
    from: message.from,
    type: message.type,
    text: message.text?.body?.substring(0, 50),
  })

  try {
    // Look up user by phone number
    const { data: userMapping } = await supabase
      .from('user_external_channels')
      .select('user_id, conversation_id')
      .eq('channel', 'whatsapp')
      .eq('external_id', message.from)
      .single()

    if (!userMapping) {
      console.log('No user mapping found for WhatsApp number:', message.from)
      // Could create a new user or queue for manual linking
      return
    }

    // Determine content type and extract content
    let contentType = 'text'
    let content = ''
    let metadata: Record<string, unknown> = {}

    switch (message.type) {
      case 'text':
        content = message.text?.body || ''
        break

      case 'image':
        contentType = 'image'
        content = '[Image]'
        metadata = {
          whatsapp_media_id: message.image?.id,
          mime_type: message.image?.mime_type,
          caption: message.image?.caption,
        }
        break

      case 'location':
        contentType = 'location'
        content = message.location?.name || message.location?.address || 'Shared location'
        metadata = {
          latitude: message.location?.latitude,
          longitude: message.location?.longitude,
          name: message.location?.name,
          address: message.location?.address,
        }
        break

      case 'document':
        contentType = 'file'
        content = message.document?.filename || '[Document]'
        metadata = {
          whatsapp_media_id: message.document?.id,
          filename: message.document?.filename,
          mime_type: message.document?.mime_type,
        }
        break

      default:
        content = `[${message.type}]`
    }

    // Insert message into database
    const { data: insertedMessage, error: insertError } = await supabase
      .from('messages')
      .insert({
        conversation_id: userMapping.conversation_id,
        sender_id: userMapping.user_id,
        content_type: contentType,
        content: content,
        metadata: {
          ...metadata,
          external_channel: 'whatsapp',
          external_message_id: message.id,
          sender_name: contact?.profile?.name,
        },
        created_at: new Date(parseInt(message.timestamp) * 1000).toISOString(),
      })
      .select()
      .single()

    if (insertError) {
      console.error('Error inserting message:', insertError)
      return
    }

    console.log('Message inserted successfully:', insertedMessage?.id)

    // Update conversation last message
    await supabase
      .from('conversations')
      .update({
        last_message_id: insertedMessage?.id,
        last_message_text: content.substring(0, 100),
        last_message_at: new Date().toISOString(),
      })
      .eq('id', userMapping.conversation_id)

    // Update user's WhatsApp session timestamp (for 24-hour window tracking)
    await supabase
      .from('user_external_channels')
      .update({
        last_session_at: new Date().toISOString(),
      })
      .eq('channel', 'whatsapp')
      .eq('external_id', message.from)

  } catch (error) {
    console.error('Error processing message:', error)
  }
}

async function processStatusUpdate(
  supabase: ReturnType<typeof createClient>,
  status: WhatsAppStatus,
  phoneNumberId: string
) {
  console.log('Processing WhatsApp status update:', {
    messageId: status.id,
    status: status.status,
    recipient: status.recipient_id,
  })

  try {
    // Map WhatsApp status to our status
    let messageStatus = 'sent'
    switch (status.status) {
      case 'sent':
        messageStatus = 'sent'
        break
      case 'delivered':
        messageStatus = 'delivered'
        break
      case 'read':
        messageStatus = 'read'
        break
      case 'failed':
        messageStatus = 'failed'
        break
    }

    // Update message status in database
    const { error } = await supabase
      .from('messages')
      .update({ status: messageStatus })
      .eq('metadata->>external_message_id', status.id)

    if (error) {
      console.error('Error updating message status:', error)
    }
  } catch (error) {
    console.error('Error processing status update:', error)
  }
}
