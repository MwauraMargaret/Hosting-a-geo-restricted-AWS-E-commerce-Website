(function () {
  var KEY = "meridian-cart";

  function read() {
    try {
      var parsed = JSON.parse(localStorage.getItem(KEY) || "[]");
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }

  function write(items) {
    localStorage.setItem(KEY, JSON.stringify(items));
    paintCount(items);
  }

  function paintCount(items) {
    var count = items.reduce(function (sum, item) { return sum + item.qty; }, 0);
    document.querySelectorAll("[data-cart-count]").forEach(function (node) {
      node.textContent = String(count);
    });
  }

  function dollars(amount) {
    return "$" + amount.toFixed(2);
  }

  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  document.querySelectorAll("[data-add]").forEach(function (button) {
    button.addEventListener("click", function () {
      var items = read();
      var id = button.getAttribute("data-id");
      var found = items.find(function (item) { return item.id === id; });
      if (found) {
        found.qty += 1;
      } else {
        items.push({
          id: id,
          name: button.getAttribute("data-name"),
          price: Number(button.getAttribute("data-price")),
          qty: 1
        });
      }
      write(items);
      var original = button.textContent;
      button.textContent = "Added";
      window.setTimeout(function () { button.textContent = original; }, 800);
    });
  });

  function renderCart(root) {
    var items = read();
    root.replaceChildren();
    if (!items.length) {
      root.appendChild(element("p", "note", "Your cart is empty."));
      return;
    }

    items.forEach(function (item) {
      var row = element("div", "cart-row");
      var info = element("div");
      info.appendChild(element("strong", null, item.name));
      info.appendChild(element("div", "note", dollars(item.price)));
      row.appendChild(info);

      var qty = element("div", "qty");
      var down = element("button", null, "−");
      down.type = "button";
      down.setAttribute("aria-label", "Decrease " + item.name);
      down.addEventListener("click", function () { change(item.id, -1); });
      var up = element("button", null, "+");
      up.type = "button";
      up.setAttribute("aria-label", "Increase " + item.name);
      up.addEventListener("click", function () { change(item.id, 1); });
      qty.appendChild(down);
      qty.appendChild(element("span", null, String(item.qty)));
      qty.appendChild(up);
      row.appendChild(qty);
      row.appendChild(element("strong", null, dollars(item.price * item.qty)));
      root.appendChild(row);
    });

    var total = items.reduce(function (sum, item) { return sum + item.price * item.qty; }, 0);
    var totalRow = element("div", "total");
    totalRow.appendChild(element("span", null, "Total"));
    totalRow.appendChild(element("strong", null, dollars(total)));
    root.appendChild(totalRow);

    var checkout = element("button", null, "Checkout");
    checkout.type = "button";
    checkout.addEventListener("click", function () {
      var status = element("p", "status", "This is a demonstration store. No payment is taken and no order is placed.");
      checkout.insertAdjacentElement("afterend", status);
      checkout.disabled = true;
    });
    root.appendChild(checkout);
  }

  function change(id, delta) {
    var items = read().map(function (item) {
      if (item.id === id) item.qty += delta;
      return item;
    }).filter(function (item) { return item.qty > 0; });
    write(items);
    var root = document.querySelector("[data-cart]");
    if (root) renderCart(root);
  }

  var cartRoot = document.querySelector("[data-cart]");
  if (cartRoot) renderCart(cartRoot);
  paintCount(read());
})();
