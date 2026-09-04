async function startUpiPayment() {
  if (state.cart.size === 0) return;

  const customerName = els.customerName.value.trim();
  const customerPhone = els.customerPhone.value.trim();

  if (!customerName && !customerPhone) {
    els.checkoutError.textContent =
      'Please enter your name or phone number before paying.';
    els.checkoutError.classList.remove('hidden');
    els.customerName.focus();
    return;
  }

  if (
    customerPhone &&
    !/^[0-9+\-\s]{6,20}$/.test(customerPhone)
  ) {
    els.checkoutError.textContent =
      'Please enter a valid phone number.';
    els.checkoutError.classList.remove('hidden');
    els.customerPhone.focus();
    return;
  }

  const upiId = String(
    state.paymentOptions.upiId || ''
  ).trim();

  if (!upiId) {
    els.checkoutError.textContent =
      'Online UPI payment is not configured right now. Please choose Pay at Counter.';
    els.checkoutError.classList.remove('hidden');
    return;
  }

  const { total } = getCartSummary();

  if (total <= 0) return;

  if (!state.clientRequestId) {
    state.clientRequestId = generateRequestId();
  }

  const payload = {
    tableNumber: state.tableNumber,
    customerName: customerName || undefined,
    customerPhone: customerPhone || undefined,
    note: els.orderNote.value.trim() || undefined,
    items: Array.from(state.cart.values()).map((line) => ({
      productId: line.product._id,
      quantity: line.quantity,
    })),
    paymentMethod: 'UPI',
    clientRequestId: state.clientRequestId,
  };

  state.pendingUpiReady = false;

  if (els.upiReferenceInput) {
    els.upiReferenceInput.value = '';
  }

  if (els.upiReferenceGroup) {
    els.upiReferenceGroup.classList.add('hidden');
  }

  /*
   * IMPORTANT:
   * Save the pending payment BEFORE opening the UPI app.
   *
   * Opening a UPI app is NOT payment confirmation.
   * The customer must return to this page,
   * enter the UTR/reference number,
   * and then press Place Order.
   */
  try {
    localStorage.setItem(
      PENDING_UPI_KEY,
      JSON.stringify({
        payload,
        cartItems: Array.from(state.cart.values()).map((line) => ({
          product: line.product,
          quantity: line.quantity,
        })),
        amount: total,
        createdAt: Date.now(),
      })
    );
  } catch (_) {}

  const upiUrl =
    `upi://pay?pa=${encodeURIComponent(upiId)}` +
    `&pn=${encodeURIComponent(
      state.paymentOptions.cafeName || 'FAST N FRESH CAFE'
    )}` +
    `&am=${encodeURIComponent(total.toFixed(2))}` +
    `&cu=INR` +
    `&tn=${encodeURIComponent(
      `Order for Table ${state.tableNumber}`
    )}`;

  /*
   * Use a real anchor click instead of:
   * window.location.href = upiUrl
   *
   * This gives Android browsers a better chance
   * of launching PhonePe / Google Pay / Paytm / BHIM etc.
   */
  const upiLink = document.createElement('a');

  upiLink.href = upiUrl;
  upiLink.target = '_self';
  upiLink.rel = 'noopener';

  document.body.appendChild(upiLink);

  upiLink.click();

  window.setTimeout(() => {
    if (upiLink.parentNode) {
      upiLink.parentNode.removeChild(upiLink);
    }
  }, 1000);
}