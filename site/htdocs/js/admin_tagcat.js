Event.observe(document, "dom:loaded", function () {
  var add = new Element("a", { href: "#" });
  add.update("Add");
  var add_div = new Element("div");
  add_div.appendChild(add);

  add.observe("click", function(add_div, ev) {
    var new_tag = new Element("input", { type: "text", name: "dep" });
    var new_li = new Element("li");
    new_li.appendChild(new_tag);
    var new_del = new Element("a", { href: "#" });
    new_del.update("Delete");
    new_del.observe("click", function(li, ev) {
      li.remove();
      ev.stop();
    }.bind(this, new_li));
    new_li.appendChild(new_del);
    $("tagcatdeps").insertBefore(new_li, add_div);
    ev.stop();
  }.bind(this, add_div));
  $("tagcatdeps").appendChild(add_div);
  $$('#tagcatdeps li').each(function(li) {
    var del = new Element("a", { href: "#" });
    del.update("Delete");
    li.appendChild(del);
    del.observe("click", function(li, ev) {
      li.remove();
      ev.stop();
    }.bind(this, li));
  });
});
