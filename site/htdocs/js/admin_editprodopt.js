document.observe("dom:loaded", function() {
  var td = $("product_option_values");
  var add_link = new Element("a", { href: "#" });
  add_link.update("Add new value");
  td.appendChild(add_link);
  var index = parseInt($("newvaluecount").value);
  add_link.observe("click", function(ev) {
    ev.stop();

    ++index;

    var div = new Element("div");
    var name = "newvalue" + index;
    var label = new Element("label", { for: name });
    label.update("Value:");
    div.appendChild(label);
    var input = new Element("input", { type: "text", name: name, id: name });
    div.appendChild(input);
    td.insertBefore(div, add_link);
    $("newvaluecount").value = index;
  });
});