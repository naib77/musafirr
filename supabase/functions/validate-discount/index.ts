// Discount Validation Edge Function
// Validates promo codes and calculates discount amounts server-side

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

interface ValidationRequest {
  code?: string
  discount_id?: string
  user_id: string
  booking_amount: number
  nights: number
  check_in_date: string
  listing_id?: string
  host_id?: string
}

interface Discount {
  id: string
  code: string | null
  name: string
  type: 'percentage' | 'fixed_amount' | 'free_nights'
  category: string
  status: string
  value: number
  max_discount_amount: number | null
  min_booking_amount: number
  free_nights_config: { stay: number; pay: number } | null
  starts_at: string
  ends_at: string | null
  total_usage_limit: number | null
  per_user_limit: number | null
  current_usage_count: number
  eligible_user_ids: string[] | null
  eligible_listing_ids: string[] | null
  eligible_host_ids: string[] | null
  min_nights: number
  max_nights: number | null
  new_users_only: boolean
  first_booking_only: boolean
  check_in_start_date: string | null
  check_in_end_date: string | null
  allowed_check_in_days: number[] | null
  stacking_behavior: string
}

serve(async (req: Request) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  try {
    const body: ValidationRequest = await req.json()

    // Validate required fields
    if (!body.user_id || !body.booking_amount || !body.nights || !body.check_in_date) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: 'Missing required fields',
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    // Initialize Supabase client
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Get discount by code or ID
    let discount: Discount | null = null

    if (body.code) {
      const { data, error } = await supabase
        .from('discounts')
        .select('*')
        .ilike('code', body.code)
        .single()

      if (error || !data) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: 'Invalid promo code',
            error_code: 'INVALID_CODE',
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }
        )
      }
      discount = data
    } else if (body.discount_id) {
      const { data, error } = await supabase
        .from('discounts')
        .select('*')
        .eq('id', body.discount_id)
        .single()

      if (error || !data) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: 'Discount not found',
            error_code: 'NOT_FOUND',
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          }
        )
      }
      discount = data
    } else {
      return new Response(
        JSON.stringify({
          valid: false,
          error: 'Either code or discount_id is required',
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    // Validate the discount
    const validationResult = await validateDiscount(supabase, discount, body)

    return new Response(JSON.stringify(validationResult), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    })
  } catch (error) {
    console.error('Error validating discount:', error)
    return new Response(
      JSON.stringify({
        valid: false,
        error: 'Internal server error',
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})

async function validateDiscount(
  supabase: ReturnType<typeof createClient>,
  discount: Discount,
  request: ValidationRequest
): Promise<{
  valid: boolean
  error?: string
  error_code?: string
  discount?: {
    id: string
    name: string
    type: string
    value: number
    discount_amount: number
    final_amount: number
  }
}> {
  const now = new Date()
  const checkInDate = new Date(request.check_in_date)

  // Check status
  if (discount.status !== 'active') {
    return {
      valid: false,
      error: 'This discount is not active',
      error_code: 'INACTIVE',
    }
  }

  // Check dates
  if (new Date(discount.starts_at) > now) {
    return {
      valid: false,
      error: 'This discount has not started yet',
      error_code: 'NOT_STARTED',
    }
  }

  if (discount.ends_at && new Date(discount.ends_at) < now) {
    return {
      valid: false,
      error: 'This discount has expired',
      error_code: 'EXPIRED',
    }
  }

  // Check total usage limit
  if (
    discount.total_usage_limit !== null &&
    discount.current_usage_count >= discount.total_usage_limit
  ) {
    return {
      valid: false,
      error: 'This discount has reached its usage limit',
      error_code: 'USAGE_LIMIT_REACHED',
    }
  }

  // Check per-user limit
  if (discount.per_user_limit !== null) {
    const { count, error } = await supabase
      .from('discount_usages')
      .select('*', { count: 'exact', head: true })
      .eq('discount_id', discount.id)
      .eq('user_id', request.user_id)
      .eq('is_reversed', false)

    if (!error && count !== null && count >= discount.per_user_limit) {
      return {
        valid: false,
        error: 'You have already used this discount',
        error_code: 'ALREADY_USED',
      }
    }
  }

  // Check minimum booking amount
  if (request.booking_amount < discount.min_booking_amount) {
    return {
      valid: false,
      error: `Minimum booking amount is ৳${discount.min_booking_amount}`,
      error_code: 'BELOW_MINIMUM_AMOUNT',
    }
  }

  // Check minimum nights
  if (request.nights < discount.min_nights) {
    return {
      valid: false,
      error: `Minimum stay is ${discount.min_nights} nights`,
      error_code: 'BELOW_MINIMUM_NIGHTS',
    }
  }

  // Check maximum nights
  if (discount.max_nights !== null && request.nights > discount.max_nights) {
    return {
      valid: false,
      error: `Maximum stay is ${discount.max_nights} nights`,
      error_code: 'ABOVE_MAXIMUM_NIGHTS',
    }
  }

  // Check eligible users
  if (
    discount.eligible_user_ids !== null &&
    !discount.eligible_user_ids.includes(request.user_id)
  ) {
    return {
      valid: false,
      error: 'You are not eligible for this discount',
      error_code: 'USER_NOT_ELIGIBLE',
    }
  }

  // Check eligible listings
  if (
    discount.eligible_listing_ids !== null &&
    request.listing_id &&
    !discount.eligible_listing_ids.includes(request.listing_id)
  ) {
    return {
      valid: false,
      error: 'This discount is not valid for this listing',
      error_code: 'LISTING_NOT_ELIGIBLE',
    }
  }

  // Check eligible hosts
  if (
    discount.eligible_host_ids !== null &&
    request.host_id &&
    !discount.eligible_host_ids.includes(request.host_id)
  ) {
    return {
      valid: false,
      error: 'This discount is not valid for this host',
      error_code: 'HOST_NOT_ELIGIBLE',
    }
  }

  // Check first booking only. Columns are tenant_id / booking_status on the
  // bookings table; a query error must FAIL CLOSED (deny) rather than grant.
  if (discount.first_booking_only) {
    const { count, error } = await supabase
      .from('bookings')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', request.user_id)
      .eq('booking_status', 'completed')

    if (error || count === null || count > 0) {
      return {
        valid: false,
        error: 'This discount is only for your first booking',
        error_code: 'NOT_FIRST_BOOKING',
      }
    }
  }

  // Check new users only — account must have been created within 30 days.
  // A lookup error fails closed.
  if (discount.new_users_only) {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('created_at')
      .eq('id', request.user_id)
      .single()

    const createdAt = profile?.created_at ? new Date(profile.created_at) : null
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    if (error || !createdAt || createdAt < thirtyDaysAgo) {
      return {
        valid: false,
        error: 'This discount is only for new users',
        error_code: 'NOT_NEW_USER',
      }
    }
  }

  // Check check-in date range
  if (
    discount.check_in_start_date &&
    checkInDate < new Date(discount.check_in_start_date)
  ) {
    return {
      valid: false,
      error: 'Check-in date is too early for this discount',
      error_code: 'CHECKIN_DATE_INVALID',
    }
  }

  if (
    discount.check_in_end_date &&
    checkInDate > new Date(discount.check_in_end_date)
  ) {
    return {
      valid: false,
      error: 'Check-in date is too late for this discount',
      error_code: 'CHECKIN_DATE_INVALID',
    }
  }

  // Check day of week restrictions
  if (discount.allowed_check_in_days !== null) {
    const dayOfWeek = checkInDate.getDay() // 0 = Sunday
    if (!discount.allowed_check_in_days.includes(dayOfWeek)) {
      return {
        valid: false,
        error: 'This discount is not valid for this check-in day',
        error_code: 'CHECKIN_DAY_NOT_ALLOWED',
      }
    }
  }

  // Calculate discount amount
  const rawDiscount = calculateDiscountAmount(
    discount,
    request.booking_amount,
    request.nights
  )
  // A discount can never be negative (a surcharge) or exceed the total.
  const discountAmount = Math.max(
    0,
    Math.min(rawDiscount, request.booking_amount)
  )

  const finalAmount = request.booking_amount - discountAmount

  return {
    valid: true,
    discount: {
      id: discount.id,
      name: discount.name,
      type: discount.type,
      value: discount.value,
      discount_amount: discountAmount,
      final_amount: finalAmount,
    },
  }
}

function calculateDiscountAmount(
  discount: Discount,
  bookingAmount: number,
  nights: number
): number {
  switch (discount.type) {
    case 'percentage': {
      let amount = bookingAmount * (discount.value / 100)
      // Apply max cap if set
      if (
        discount.max_discount_amount !== null &&
        amount > discount.max_discount_amount
      ) {
        amount = discount.max_discount_amount
      }
      return amount
    }

    case 'fixed_amount': {
      // Don't exceed booking amount
      return Math.min(discount.value, bookingAmount)
    }

    case 'free_nights': {
      if (
        discount.free_nights_config &&
        nights > 0 &&
        nights >= discount.free_nights_config.stay
      ) {
        // Never negative: a config with pay >= stay gives zero free nights.
        const freeNights = Math.max(
          0,
          discount.free_nights_config.stay - discount.free_nights_config.pay
        )
        const perNightRate = bookingAmount / nights
        return freeNights * perNightRate
      }
      return 0
    }

    default:
      return 0
  }
}
