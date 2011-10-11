/* stuff for every admin page */
/* mark accesskeys */
document.observe("dom:loaded", function() {
  $$("label").each(function(label) {
    if (!label.htmlFor)
      return;
    var inp = $(label.htmlFor);
    if (!inp || !inp.accessKey)
      return;
    
    /* look for the accesskey in the label text */
    var kids = label.childNodes;
    var re = new RegExp(inp.accessKey, "i");
    for (var i = 0; i < kids.length; ++i) {
      var kid = kids[i];
      if (kid.nodeType &&
	  kid.nodeType == Node.TEXT_NODE &&
	  re.test(kid.data)) {
	var next = i == kids.length-1 ? null : kids[i+1];
	var m = re.exec(kid.data);
	var nn = kid.splitText(m.index);
	var nn2 = nn.splitText(1);
	var span = new Element("span", { className: "accesskeyx" });
	span.appendChild(nn);
	label.insertBefore(span, nn2);
	return;
      }
    }
  });

  $$(".focusme:first").each(function(element) { element.focus() });

  // warn if a user has caps on typing into a password field
  $$("input[type=password]").each(function(ele) {
    var iscaps = null;
    var span = null;
    ele.observe("keypress", function(ev) {
      var s = String.fromCharCode(ev.keyCode || ev.which);
      
      var new_iscaps = iscaps;
      if (ev.which == 20) {
	if (new_iscaps != null)
	  new_iscaps = !new_iscaps;
      }
      else if (s.toUpperCase() !== s.toLowerCase()) {
	new_iscaps = ((s.toUpperCase() === s
		   && !ev.shiftKey)
		  || (s.toLowerCase() === s
		      && ev.shiftKey));
      }
      if (new_iscaps && !iscaps) {
	if (!span) {
	  span = new Element("span", { className: "bse_capswarning" });
	  span.update("Check Caps Lock");
	}
	ele.parentNode.insertBefore(span, this.nextSibling);
      }
      else if (iscaps && !new_iscaps) {
	span.remove();
      }
      iscaps = new_iscaps;
    }.bindAsEventListener(ele));
    ele.observe("blur", function(ev) {
      if (iscaps) {
	span.remove();
	iscaps = null;
      }
    }.bindAsEventListener(ele));
  });
});