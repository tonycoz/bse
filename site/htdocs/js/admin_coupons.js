(function($) {
    var $form = $("#coupon_form");
    var $classid = $("select[name=classid]", $form);
    $classid.on("change", function(ev) {
	var val = ev.target.value;
	var val_sel = "[data-behaviour=" + val + "]";
	$("[data-behaviour]", $form).hide();
	$("[data-behaviour] input, [data-behaviour] select", $form).prop("disabled", true);
	$(val_sel + " input, " + val_sel + " select", $form).prop("disabled", false);
	$(val_sel, $form).show();
	
    });
})(jQuery);
