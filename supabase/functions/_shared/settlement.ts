// The one decision sslcommerz-ipn makes, as a pure function.
//
// Everything the IPN handler knows after re-validating a transaction with
// SSLCommerz goes in; what to write to `payments.status` and whether the
// booking may be marked paid comes out. It is a separate module because the
// handler itself can only be exercised with a real gateway session, and the
// second QA round (2026-09-19, scenario 41) found a case that no sandbox run
// had reached: a guest starts paying, the booking is cancelled or rejected
// while the bank page is open, and the guest completes the payment anyway.
// The validation passes — the money did move — and the handler marked the
// booking paid, which posts the host's earning for a stay that will not
// happen. So the booking's own state is now an input, and a payment that
// lands on a booking no longer open is HELD, exactly like a risk-flagged one,
// for an admin to refund or release from the console (136).

export interface SettlementInput {
  /** SSLCommerz's status for the validated transaction. */
  gatewayStatus: string | null | undefined;
  /** Amount SSLCommerz says was paid, in the store currency. */
  gatewayAmount: unknown;
  /** Transaction id SSLCommerz echoes back. */
  gatewayTranId: string | null | undefined;
  /** SSLCommerz's fraud screen: "0" is clean, anything else is a flag. */
  riskLevel: unknown;
  /** What sslcommerz-init recorded when the guest started paying. */
  expectedAmount: number;
  expectedTranId: string;
  /** The booking as it is NOW, not as it was when payment started. */
  bookingStatus: string | null | undefined;
  bookingPaymentStatus: string | null | undefined;
}

export type SettlementOutcome =
  | { kind: "failed"; reason: "not_valid" | "amount_mismatch" | "tran_mismatch" }
  | { kind: "held"; reason: "risk_flag" | "booking_not_open" | "already_settled" }
  | { kind: "paid" };

/** Statuses a payment may settle against. Anything else is a stay that is
 *  not going to happen — pending (host has not accepted; init refuses these,
 *  so one arriving here means the booking was rejected or expired after the
 *  bank page opened), rejected, cancelled, completed. */
const OPEN_BOOKING_STATUSES = new Set(["confirmed", "active"]);

export function decideSettlement(input: SettlementInput): SettlementOutcome {
  const status = String(input.gatewayStatus ?? "").toUpperCase();
  if (status !== "VALID" && status !== "VALIDATED") {
    return { kind: "failed", reason: "not_valid" };
  }
  const amount = Number(input.gatewayAmount);
  if (!Number.isFinite(amount) || Math.abs(amount - input.expectedAmount) >= 0.01) {
    return { kind: "failed", reason: "amount_mismatch" };
  }
  if ((input.gatewayTranId ?? "") !== input.expectedTranId) {
    return { kind: "failed", reason: "tran_mismatch" };
  }

  // From here the money is real. The question is only whether the BOOKING
  // may be marked paid, and holding is always the safe answer.
  //
  // The booking's state is checked BEFORE the fraud flag, deliberately. Both
  // hold, but the admin's next step differs: a flagged payment on an open
  // booking is released or rejected; a payment on a cancelled booking can
  // only be refunded — releasing it would mark a cancelled stay paid and
  // post the host an earning for it. The reason the admin is shown must be
  // the one that tells them which button not to press.
  if (!OPEN_BOOKING_STATUSES.has(String(input.bookingStatus ?? ""))) {
    return { kind: "held", reason: "booking_not_open" };
  }
  // A cash confirmation or an earlier IPN already settled it; a second real
  // payment must not be silently absorbed as "paid" — it is a double charge
  // for an admin to refund.
  if (input.bookingPaymentStatus === "paid") {
    return { kind: "held", reason: "already_settled" };
  }
  const riskLevel = input.riskLevel != null ? String(input.riskLevel) : null;
  if (riskLevel !== null && riskLevel !== "0") {
    return { kind: "held", reason: "risk_flag" };
  }
  return { kind: "paid" };
}

/** What `payments.status` becomes for an outcome. */
export function paymentStatusFor(outcome: SettlementOutcome): "paid" | "pending_review" | "failed" {
  switch (outcome.kind) {
    case "paid":
      return "paid";
    case "held":
      return "pending_review";
    case "failed":
      return "failed";
  }
}
