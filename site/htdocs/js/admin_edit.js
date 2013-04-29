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

    // $$("[data-sort], [data-reverse]").each(function(e) {
    // 	e.observe("click", function(ev) {
    // 	    var id = $("id").textContent;
    // 	    var sorter = e.getAttribute("data-sort");
    // 	    if (!sorter) sorter = "";
    // 	    var reverse = e.getAttribute("data-reverse");
    // 	    if (!reverse) reverse = 0;
    // 	    new Ajax.Request
    // 	    ("/cgi-bin/admin/reorder.pl",
    // 	     {
    // 		 parameters:{
    // 		     parentid: id,
    // 		     sort: sorter,
    // 		     reverse: reverse
    // 		 },
    // 		 onSuccess: function(resp) {
    // 		     var json = resp.responseJSON;
    // 		     if (json.success) {
    // 			 var new_order = json.kids;
    // 			 var kids = new_order.map(function(id) { return $("child" + id); });
    // 			 if (kids.length) {
    // 			     var parent = kids[0].parentNode;
    // 			     kids.each(function(kid) {
    // 				 parent.removeChild(kid);
    // 				 parent.appendChild(kid);
    // 			     });
    // 			 }
    // 		     }
    // 		     // else ignore error for now
    // 		 }
    // 	     });
    // 	    ev.stop();
    // 	});
    // });
});
