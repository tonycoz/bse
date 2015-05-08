(function($) {
    $(function() {
	$(".tag").each(function() {
	    var closed = this;
	    var input = $("input", this);
	    var del = $("<a/>", { href: "#" });
	    del.text("Delete");
	    del.click(function () {
		closed.remove();
		return true;
	    });
	    $(this).append(del);
	});
	$(".tags").each(function() {
	    var tags = $(this);
	    var fname = this.dataset["name"];
	    if (!fname)
		fname = "tag";
	    var add_div = $("<div/>", { "class": "tag_add" });
	    var add_a = $("<a/>", { href: "#" });
	    add_div.append(add_a);
	    add_a.text("Add");
	    add_a.click(function() {
		var inp = $("<input/>",
			   { type: "text",
			     name: fname });
		var div = $("<div/>", { "class": "tag" });
		div.append(inp);
		var del = $("<a/>", { href: "#" });
		div.append(del);
		del.text("Delete");
		del.click(function() {
		    div.remove();
		    return true;
		});
		add_div.before(div);
		return true;
	    });
	    tags.append(add_div);
	});
    });
})(jQuery);