// Messenger Webhook Edge Function
// Handles incoming messages and webhook verification from Facebook Messenger Platform

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const VERIFY_TOKEN = Deno.env.get('MESSENGER_WEBHOOK_VERIFY_TOKEN') || ''
const PAGE_ACCESS_TOKEN = Deno.env.get('MESSENGER_PAGE_ACCESS_TOKEN') || ''
const APP_SECRET = Deno.env.get('MESSENGER_APP_SECRET') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

/** Verify Meta's `X-Hub-Signature-256` = 'sha256=' + HMAC-SHA256(rawBody, appSecret).
 *  Without this, anyone can POST forged events to this public endpoint and inject
 *  messages under a linked user's identity via the service-role key. */
async function verifyMetaSignature(
  rawBody: string,
  signatureHeader: string | null,
  appSecret: string,
): Promise<boolean> {
  if (!appSecret || !signatureHeader) return false
  const expected = signatureHeader.startsWith('sha256=')
    ? signatureHeader.slice(7)
    : signatureHeader
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(appSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody))
  const computed = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  if (computed.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < computed.length; i++) diff |= computed.charCodeAt(i) ^ expected.charCodeAt(i)
  return diff === 0
}

interface MessengerAttachment {
  type: string
  payload: {
    url?: string
    coordinates?: {
      lat: number
      long: number
    }
    title?: string
  }
}

interface MessengerMessage {
  mid: string
  text?: string
  attachments?: MessengerAttachment[]
  quick_reply?: {
    payload: string
  }
  reply_to?: {
    mid: string
  }
}

interface MessengerPostback {
  payload: string
  title?: string
  referral?: {
    ref: string
    source: string
    type: string
  }
}

interface MessengerReferral {
  ref: string
  source: string
  type: string
  ad_id?: string
}

interface MessagingEvent {
  sender: { id: string }
  recipient: { id: string }
  timestamp: number
  message?: MessengerMessage
  postback?: MessengerPostback
  referral?: MessengerReferral
  read?: { watermark: number }
  delivery?: { mids: string[]; watermark: number }
}

interface WebhookEntry {
  id: string
  time: number
  messaging: MessagingEvent[]
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

    console.log('Messenger Webhook Verification Request:', { mode, token, challenge: challenge?.substring(0, 20) })

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
      // Verify the payload actually came from Meta before trusting anything in it.
      const rawBody = await req.text()
      const signatureOk = await verifyMetaSignature(
        rawBody,
        req.headers.get('x-hub-signature-256'),
        APP_SECRET,
      )
      if (!signatureOk) {
        console.error('Messenger webhook: invalid signature')
        return new Response('Invalid signature', { status: 401 })
      }
      const payload: WebhookPayload = JSON.parse(rawBody)

      if (payload.object !== 'page') {
        return new Response('Invalid object type', { status: 400 })
      }

      // Initialize Supabase client
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

      // Process each entry
      for (const entry of payload.entry) {
        const pageId = entry.id

        for (const event of entry.messaging) {
          // Handle different event types
          if (event.message) {
            await processIncomingMessage(supabase, event, pageId)
          } else if (event.postback) {
            await processPostback(supabase, event, pageId)
          } else if (event.referral) {
            await processReferral(supabase, event, pageId)
          } else if (event.read) {
            await processReadReceipt(supabase, event, pageId)
          } else if (event.delivery) {
            await processDeliveryReceipt(supabase, event, pageId)
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
  event: MessagingEvent,
  pageId: string
) {
  const senderId = event.sender.id
  const message = event.message!

  console.log('Processing incoming Messenger message:', {
    from: senderId,
    text: message.text?.substring(0, 50),
    hasAttachments: !!message.attachments?.length,
  })

  try {
    // Look up user by Messenger PSID
    const { data: userMapping } = await supabase
      .from('user_external_channels')
      .select('user_id, conversation_id')
      .eq('channel', 'messenger')
      .eq('external_id', senderId)
      .single()

    // If no mapping exists, try to get user profile and create mapping
    if (!userMapping) {
      console.log('No user mapping found for Messenger PSID:', senderId)
      // In production, you might want to:
      // 1. Fetch user profile from Messenger API
      // 2. Create a new user or queue for manual linking
      // 3. Send a welcome message with linking instructions
      return
    }

    // Determine content type and extract content
    let contentType = 'text'
    let content = ''
    let metadata: Record<string, unknown> = {}

    if (message.text) {
      content = message.text
    } else if (message.attachments && message.attachments.length > 0) {
      const attachment = message.attachments[0]

      switch (attachment.type) {
        case 'image':
          contentType = 'image'
          content = '[Image]'
          metadata = {
            url: attachment.payload.url,
          }
          break

        case 'video':
          contentType = 'file'
          content = '[Video]'
          metadata = {
            url: attachment.payload.url,
            file_type: 'video',
          }
          break

        case 'audio':
          contentType = 'file'
          content = '[Audio]'
          metadata = {
            url: attachment.payload.url,
            file_type: 'audio',
          }
          break

        case 'file':
          contentType = 'file'
          content = attachment.payload.title || '[File]'
          metadata = {
            url: attachment.payload.url,
          }
          break

        case 'location':
          contentType = 'location'
          content = attachment.payload.title || 'Shared location'
          metadata = {
            latitude: attachment.payload.coordinates?.lat,
            longitude: attachment.payload.coordinates?.long,
          }
          break

        default:
          content = `[${attachment.type}]`
      }
    }

    // Handle quick reply
    if (message.quick_reply) {
      metadata.quick_reply_payload = message.quick_reply.payload
    }

    // Handle reply to
    if (message.reply_to) {
      metadata.reply_to_external_id = message.reply_to.mid
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
          external_channel: 'messenger',
          external_message_id: message.mid,
        },
        created_at: new Date(event.timestamp).toISOString(),
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

    // Update last interaction timestamp
    await supabase
      .from('user_external_channels')
      .update({
        last_interaction_at: new Date().toISOString(),
      })
      .eq('channel', 'messenger')
      .eq('external_id', senderId)

  } catch (error) {
    console.error('Error processing message:', error)
  }
}

async function processPostback(
  supabase: ReturnType<typeof createClient>,
  event: MessagingEvent,
  pageId: string
) {
  const senderId = event.sender.id
  const postback = event.postback!

  console.log('Processing Messenger postback:', {
    from: senderId,
    payload: postback.payload,
    title: postback.title,
  })

  // Handle postback payloads (button clicks)
  switch (postback.payload) {
    case 'GET_STARTED':
      // Send welcome message
      await sendWelcomeMessage(senderId)
      break

    case 'BROWSE_LISTINGS':
      // Could send a carousel of featured listings
      console.log('User wants to browse listings')
      break

    case 'MY_BOOKINGS':
      // Could send user's booking summary
      console.log('User wants to see bookings')
      break

    case 'BECOME_HOST':
      // Send host information
      console.log('User interested in becoming a host')
      break

    default:
      console.log('Unhandled postback payload:', postback.payload)
  }
}

async function processReferral(
  supabase: ReturnType<typeof createClient>,
  event: MessagingEvent,
  pageId: string
) {
  const senderId = event.sender.id
  const referral = event.referral!

  console.log('Processing Messenger referral:', {
    from: senderId,
    ref: referral.ref,
    source: referral.source,
  })

  // Referrals can come from:
  // - m.me links with ref parameter
  // - Ads
  // - Messenger Codes

  // Log for analytics
  await supabase
    .from('analytics_events')
    .insert({
      event_type: 'messenger_referral',
      user_psid: senderId,
      metadata: {
        ref: referral.ref,
        source: referral.source,
        type: referral.type,
        ad_id: referral.ad_id,
      },
    })
    .catch((err: Error) => console.log('Analytics insert failed:', err))
}

async function processReadReceipt(
  supabase: ReturnType<typeof createClient>,
  event: MessagingEvent,
  pageId: string
) {
  const senderId = event.sender.id
  const watermark = event.read!.watermark

  console.log('Processing read receipt:', {
    from: senderId,
    watermark: new Date(watermark).toISOString(),
  })

  // Update all messages sent before watermark as read
  // Note: This requires tracking which messages we sent to which PSID
}

async function processDeliveryReceipt(
  supabase: ReturnType<typeof createClient>,
  event: MessagingEvent,
  pageId: string
) {
  const senderId = event.sender.id
  const delivery = event.delivery!

  console.log('Processing delivery receipt:', {
    from: senderId,
    messageIds: delivery.mids,
    watermark: new Date(delivery.watermark).toISOString(),
  })

  // Update message statuses to 'delivered'
  if (delivery.mids && delivery.mids.length > 0) {
    for (const mid of delivery.mids) {
      await supabase
        .from('messages')
        .update({ status: 'delivered' })
        .eq('metadata->>external_message_id', mid)
    }
  }
}

async function sendWelcomeMessage(recipientId: string) {
  const apiUrl = `https://graph.facebook.com/v18.0/me/messages?access_token=${PAGE_ACCESS_TOKEN}`

  const messageData = {
    recipient: { id: recipientId },
    messaging_type: 'RESPONSE',
    message: {
      text: "Welcome to Musaafir! I'm here to help you find your perfect stay in Bangladesh. What would you like to do?",
      quick_replies: [
        {
          content_type: 'text',
          title: 'Browse listings',
          payload: 'BROWSE_LISTINGS',
        },
        {
          content_type: 'text',
          title: 'My bookings',
          payload: 'MY_BOOKINGS',
        },
        {
          content_type: 'text',
          title: 'Become a host',
          payload: 'BECOME_HOST',
        },
      ],
    },
  }

  try {
    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(messageData),
    })

    if (!response.ok) {
      const error = await response.json()
      console.error('Error sending welcome message:', error)
    } else {
      console.log('Welcome message sent successfully')
    }
  } catch (error) {
    console.error('Error sending welcome message:', error)
  }
}
