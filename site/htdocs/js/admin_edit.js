Event.observe(document, "dom:loaded", function () {
  var add = new Element("a", { href: "#" });
  add.update("Add");
  var add_div = new Element("div");
  add_div.appendChild(add);

  add.observe("click", function(add_div, ev) {
    var new_tag = new Element("input", { type: "text", name: "tags" });
    var new_div = new Element("div", { className: "tag" });
    new_div.appendChild(new_tag);
    var new_del = new Element("a", { href: "#" });
    new_del.update("Delete");
    new_del.observe("click", function(div, ev) {
      new_div.remove();
      ev.stop();
    }.bind(this, new_div));
    new_div.appendChild(new_del);
    $("tags").insertBefore(new_div, add_div);
    ev.stop();
  }.bind(this, add_div));
    if ($("#tags")) {
	$("tags").appendChild(add_div);
	$$('#tags div.tag').each(function(div) {
	    var del = new Element("a", { href: "#" });
	    del.update("Delete");
	    div.appendChild(del);
	    del.observe("click", function(div, ev) {
		div.remove();
		ev.stop();
	    }.bind(this, div));
	});
    }
});
