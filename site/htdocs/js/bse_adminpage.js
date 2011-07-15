document.observe("dom:loaded", function() {
  new Ajax.Request("/cgi-bin/admin/admin.pl", {
    onSuccess: function(resp) {
      if (resp.responseJSON
	 && resp.responseJSON.success != 0
	 && resp.responseJSON.warnings.length != 0) {
	$("admin_messages").hide();
	var warnings = resp.responseJSON.warnings;
	for (var i = 0; i < warnings.length; ++i) {
	  var div = new Element("div");
	  div.update(warnings[i]);
	  $("admin_messages").appendChild(div);
	}

	var note = new Element("input", { 
	  className: "admin_warning_flag",
	  type: "button",
	  value: "Warnings!"
	});

	$("admin_messages_flag").appendChild(note);
	note.observe("click", function () {
	  $("admin_messages").toggle();
	});
      }
    },
    parameters: {
      id: admin_article_id,
      a_warnings: 1
    }
  });		   
});