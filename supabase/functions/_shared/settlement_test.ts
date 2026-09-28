import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideSettlement, paymentStatusFor, type SettlementInput } from "./settlement.ts";

const clean: SettlementInput = {
  gatewayStatus: "VALID",
  gatewayAmount: "1500.00",
  gatewayTranId: "MSFR-AAAA-BBBB",
  riskLevel: "0",
  expectedAmount: 1500,
  expectedTranId: "MSFR-AAAA-BBBB",
  bookingStatus: "confirmed",
  bookingPaymentStatus: "unpaid",
};

Deno.test("a clean validated payment on a confirmed booking is paid", () => {
  assertEquals(decideSettlement(clean), { kind: "paid" });
  assertEquals(paymentStatusFor(decideSettlement(clean)), "paid");
});

Deno.test("VALIDATED is as good as VALID, and a checked-in stay can still pay", () => {
  assertEquals(
    decideSettlement({ ...clean, gatewayStatus: "VALIDATED", bookingStatus: "active" }),
    { kind: "paid" },
  );
});

Deno.test("anything but VALID/VALIDATED fails, before the booking is even looked at", () => {
  for (const s of ["FAILED", "CANCELLED", "INVALID_TRANSACTION", "", null, undefined]) {
    assertEquals(decideSettlement({ ...clean, gatewayStatus: s }), {
      kind: "failed",
      reason: "not_valid",
    });
  }
});

Deno.test("the amount must match what init recorded, to the paisa", () => {
  assertEquals(decideSettlement({ ...clean, gatewayAmount: "1499.98" }), {
    kind: "failed",
    reason: "amount_mismatch",
  });
  assertEquals(decideSettlement({ ...clean, gatewayAmount: "1500.004" }), { kind: "paid" });
  assertEquals(decideSettlement({ ...clean, gatewayAmount: "abc" }), {
    kind: "failed",
    reason: "amount_mismatch",
  });
});

Deno.test("a validation for a different tran_id is not ours", () => {
  assertEquals(decideSettlement({ ...clean, gatewayTranId: "MSFR-OTHER" }), {
    kind: "failed",
    reason: "tran_mismatch",
  });
});

Deno.test("a fraud flag holds the payment; an unrecognised risk code is not a clean one", () => {
  for (const r of ["1", 1, "2", "high"]) {
    assertEquals(decideSettlement({ ...clean, riskLevel: r }), {
      kind: "held",
      reason: "risk_flag",
    });
  }
  // SSLCommerz omitting the field entirely is treated as clean (pre-136 behaviour).
  assertEquals(decideSettlement({ ...clean, riskLevel: null }), { kind: "paid" });
});

Deno.test("scenario 41: paying after the booking was cancelled or rejected is HELD, not paid", () => {
  for (const s of ["cancelled", "rejected", "completed", "pending", null, ""]) {
    const out = decideSettlement({ ...clean, bookingStatus: s });
    assertEquals(out, { kind: "held", reason: "booking_not_open" }, `status ${s}`);
    assertEquals(paymentStatusFor(out), "pending_review");
  }
});

Deno.test("a second real payment on an already-paid booking is held as a double charge", () => {
  assertEquals(decideSettlement({ ...clean, bookingPaymentStatus: "paid" }), {
    kind: "held",
    reason: "already_settled",
  });
});

Deno.test("a closed booking outranks the risk flag: the admin must refund, never release", () => {
  // admin_release_payment marks the booking paid. On a cancelled booking that
  // is the wrong button, so the reason shown has to be the booking's state.
  assertEquals(decideSettlement({ ...clean, riskLevel: "1", bookingStatus: "cancelled" }), {
    kind: "held",
    reason: "booking_not_open",
  });
  assertEquals(
    decideSettlement({ ...clean, riskLevel: "1", bookingPaymentStatus: "paid" }),
    { kind: "held", reason: "already_settled" },
  );
});
