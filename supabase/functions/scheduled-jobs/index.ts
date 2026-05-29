// Supabase Edge Function: Scheduled Jobs
// This function handles scheduled tasks:
// 1. Expire pending bookings older than 24 hours
// 2. Auto-reveal reviews older than 14 days
// 3. Send review reminders at 3 and 7 days
//
// Can be triggered by:
// - External cron service (cron-job.org, GitHub Actions)
// - Supabase scheduled functions
// - Manual invocation for testing

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface JobResult {
  job: string
  processed: number
  error?: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authorization (use service role key or a secret)
    const authHeader = req.headers.get('Authorization')
    const expectedKey = Deno.env.get('CRON_SECRET') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !authHeader.includes(expectedKey || '')) {
      // For scheduled functions, check if it's from Supabase scheduler
      const isScheduled = req.headers.get('x-supabase-scheduled') === 'true'
      if (!isScheduled && !authHeader) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Create Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Parse request body to determine which jobs to run
    let jobsToRun = ['expire-bookings', 'reveal-reviews', 'send-reminders']

    try {
      const body = await req.json()
      if (body.jobs && Array.isArray(body.jobs)) {
        jobsToRun = body.jobs
      }
    } catch {
      // No body or invalid JSON - run all jobs
    }

    const results: JobResult[] = []

    // Job 1: Expire stale bookings
    if (jobsToRun.includes('expire-bookings')) {
      const expireResult = await expireStaleBookings(supabase)
      results.push(expireResult)
    }

    // Job 2: Auto-reveal old reviews
    if (jobsToRun.includes('reveal-reviews')) {
      const revealResult = await autoRevealReviews(supabase)
      results.push(revealResult)
    }

    // Job 3: Send review reminders
    if (jobsToRun.includes('send-reminders')) {
      const reminderResult = await sendReviewReminders(supabase)
      results.push(reminderResult)
    }

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: new Date().toISOString(),
        results,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Scheduled jobs error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

// ============================================================================
// Job: Expire Stale Bookings (24 hours)
// ============================================================================
async function expireStaleBookings(supabase: any): Promise<JobResult> {
  try {
    const cutoffTime = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

    // Find pending bookings older than 24 hours
    const { data: staleBookings, error: fetchError } = await supabase
      .from('bookings')
      .select(`
        id,
        listing_id,
        tenant_id,
        listings!inner(title, owner_id)
      `)
      .eq('booking_status', 'pending')
      .lt('created_at', cutoffTime)

    if (fetchError) throw fetchError
    if (!staleBookings || staleBookings.length === 0) {
      return { job: 'expire-bookings', processed: 0 }
    }

    let processed = 0

    for (const booking of staleBookings) {
      // Update booking to rejected
      const { error: updateError } = await supabase
        .from('bookings')
        .update({
          booking_status: 'rejected',
          rejection_reason: 'Booking request expired after 24 hours without host response',
        })
        .eq('id', booking.id)

      if (updateError) {
        console.error(`Failed to expire booking ${booking.id}:`, updateError)
        continue
      }

      // Get guest name for notification
      const { data: guest } = await supabase
        .from('profiles')
        .select('full_name')
        .eq('id', booking.tenant_id)
        .single()

      const listingTitle = booking.listings?.title || 'the property'
      const hostId = booking.listings?.owner_id
      const guestName = guest?.full_name || 'A guest'

      // Notify guest
      await supabase.from('notifications').insert({
        user_id: booking.tenant_id,
        type: 'booking_rejected',
        title: 'Booking Request Expired',
        body: `Your booking request for ${listingTitle} expired. The host did not respond within 24 hours.`,
        priority: 'normal',
        action_url: `/trips/${booking.id}`,
        data: {
          booking_id: booking.id,
          listing_id: booking.listing_id,
          reason: 'expired',
        },
      })

      // Notify host
      if (hostId) {
        await supabase.from('notifications').insert({
          user_id: hostId,
          type: 'booking_cancelled',
          title: 'Booking Request Expired',
          body: `A booking request from ${guestName} for ${listingTitle} expired because you did not respond within 24 hours.`,
          priority: 'normal',
          action_url: `/host/reservations/${booking.id}`,
          data: {
            booking_id: booking.id,
            listing_id: booking.listing_id,
            reason: 'expired',
          },
        })
      }

      processed++
    }

    console.log(`Expired ${processed} stale bookings`)
    return { job: 'expire-bookings', processed }
  } catch (error) {
    console.error('Error expiring bookings:', error)
    return { job: 'expire-bookings', processed: 0, error: error.message }
  }
}

// ============================================================================
// Job: Auto-Reveal Reviews (14 days)
// ============================================================================
async function autoRevealReviews(supabase: any): Promise<JobResult> {
  try {
    const cutoffTime = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString()

    // Find unrevealed reviews older than 14 days
    const { data: oldReviews, error: fetchError } = await supabase
      .from('reviews')
      .select(`
        id,
        booking_id,
        listing_id,
        reviewer_id,
        reviewee_id,
        review_type,
        overall_rating
      `)
      .eq('is_revealed', false)
      .lt('created_at', cutoffTime)

    if (fetchError) throw fetchError
    if (!oldReviews || oldReviews.length === 0) {
      return { job: 'reveal-reviews', processed: 0 }
    }

    let processed = 0

    for (const review of oldReviews) {
      // Reveal the review
      const { error: updateError } = await supabase
        .from('reviews')
        .update({
          is_revealed: true,
          revealed_at: new Date().toISOString(),
        })
        .eq('id', review.id)

      if (updateError) {
        console.error(`Failed to reveal review ${review.id}:`, updateError)
        continue
      }

      // Get listing info for notification
      let listingTitle = 'the property'
      if (review.listing_id) {
        const { data: listing } = await supabase
          .from('listings')
          .select('title')
          .eq('id', review.listing_id)
          .single()
        listingTitle = listing?.title || listingTitle
      }

      // Notify the reviewee
      const notificationBody = review.review_type === 'guest_to_host'
        ? `You received a ${review.overall_rating} star review for ${listingTitle}`
        : `You received a ${review.overall_rating} star review from a host`

      const actionUrl = review.review_type === 'guest_to_host'
        ? `/listing/${review.listing_id}/reviews`
        : '/profile/reviews'

      await supabase.from('notifications').insert({
        user_id: review.reviewee_id,
        type: 'review_received',
        title: 'New Review Available',
        body: notificationBody,
        priority: 'normal',
        action_url: actionUrl,
        data: {
          review_id: review.id,
          booking_id: review.booking_id,
          rating: review.overall_rating,
          review_type: review.review_type,
          auto_revealed: true,
        },
      })

      processed++
    }

    console.log(`Auto-revealed ${processed} reviews`)
    return { job: 'reveal-reviews', processed }
  } catch (error) {
    console.error('Error revealing reviews:', error)
    return { job: 'reveal-reviews', processed: 0, error: error.message }
  }
}

// ============================================================================
// Job: Send Review Reminders (3 and 7 days)
// ============================================================================
async function sendReviewReminders(supabase: any): Promise<JobResult> {
  try {
    const now = Date.now()
    const threeDaysAgo = new Date(now - 3 * 24 * 60 * 60 * 1000)
    const threeDaysAgoPlus1h = new Date(now - 3 * 24 * 60 * 60 * 1000 - 60 * 60 * 1000)
    const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000)
    const sevenDaysAgoPlus1h = new Date(now - 7 * 24 * 60 * 60 * 1000 - 60 * 60 * 1000)

    // Find completed bookings eligible for reminders
    const { data: completedBookings, error: fetchError } = await supabase
      .from('bookings')
      .select(`
        id,
        listing_id,
        tenant_id,
        completed_at,
        listings!inner(title, owner_id)
      `)
      .eq('booking_status', 'completed')
      .not('completed_at', 'is', null)
      .or(`completed_at.gte.${threeDaysAgoPlus1h.toISOString()},completed_at.gte.${sevenDaysAgoPlus1h.toISOString()}`)
      .or(`completed_at.lt.${threeDaysAgo.toISOString()},completed_at.lt.${sevenDaysAgo.toISOString()}`)

    if (fetchError) throw fetchError
    if (!completedBookings || completedBookings.length === 0) {
      return { job: 'send-reminders', processed: 0 }
    }

    let processed = 0

    for (const booking of completedBookings) {
      const completedAt = new Date(booking.completed_at)
      const daysSinceCompletion = Math.floor((now - completedAt.getTime()) / (24 * 60 * 60 * 1000))

      // Only send reminders at 3 or 7 days
      if (daysSinceCompletion !== 3 && daysSinceCompletion !== 7) {
        continue
      }

      const listingTitle = booking.listings?.title || 'your recent stay'
      const hostId = booking.listings?.owner_id

      // Check if guest has already reviewed
      const { data: guestReview } = await supabase
        .from('reviews')
        .select('id')
        .eq('booking_id', booking.id)
        .eq('review_type', 'guest_to_host')
        .single()

      // Check if host has already reviewed
      const { data: hostReview } = await supabase
        .from('reviews')
        .select('id')
        .eq('booking_id', booking.id)
        .eq('review_type', 'host_to_guest')
        .single()

      // Send reminder to guest if they haven't reviewed
      if (!guestReview) {
        await supabase.from('notifications').insert({
          user_id: booking.tenant_id,
          type: 'review_reminder',
          title: "Don't Forget to Review!",
          body: `Share your experience at ${listingTitle}. Your review helps other travelers!`,
          priority: 'normal',
          action_url: `/review/${booking.id}/guest`,
          data: {
            booking_id: booking.id,
            listing_id: booking.listing_id,
            reminder_day: daysSinceCompletion,
          },
        })
        processed++
      }

      // Send reminder to host if they haven't reviewed
      if (!hostReview && hostId) {
        await supabase.from('notifications').insert({
          user_id: hostId,
          type: 'review_reminder',
          title: 'Review Your Guest',
          body: `Don't forget to review your guest from ${listingTitle}. Your feedback helps the community!`,
          priority: 'normal',
          action_url: `/review/${booking.id}/host`,
          data: {
            booking_id: booking.id,
            listing_id: booking.listing_id,
            reminder_day: daysSinceCompletion,
          },
        })
        processed++
      }
    }

    console.log(`Sent ${processed} review reminders`)
    return { job: 'send-reminders', processed }
  } catch (error) {
    console.error('Error sending reminders:', error)
    return { job: 'send-reminders', processed: 0, error: error.message }
  }
}
