(function($) {
    $(function() {
	'use strict';
	$.Mustache.options.warnOnMissingTemplates = true;
	$.Mustache.addFromDom();
	$(".tag").each(function() {
	    var closed = this;
	    var input = $("input", this);
	    var del = $($.Mustache.render("del_link", { }));
	    var del_click = $(".tag_delete_click", del);
	    if (del_click.length == 0)
		del_click = del;
	    del_click.click(function () {
		closed.remove();
		return false;
	    });
	    input.after(del);
	});
	$(".tags").each(function() {
	    var tags = $(this);
	    var fname = this.dataset["name"];
	    if (!fname)
		fname = "tag";
	    var add_div = $($.Mustache.render("add_link", {
		fname: fname
	    }));
	    var add_a = $(".tag_add_click", add_div);
	    add_a.click(function() {
		var div_text = $.Mustache.render("tag_field", {
		    fname: fname
		});
		var div = $(div_text);
		var del = $(".tag_delete_click", div);
		del.click(function() {
		    div.remove();
		    return false;
		});
		add_div.before(div);

		return false;
	    });
	    tags.append(add_div);
	});
    });
})(jQuery);