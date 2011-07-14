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
    var state = { iscaps: null };
    ele.observe("keypress", function(ev, state) {
      var s = String.fromCharCode(ev.keyCode || ev.which);
      
      var iscaps = state.iscaps;
      if (ev.which == 20) {
	if (iscaps != null)
	  iscaps = !iscaps;
      }
      else if (s.toUpperCase() !== s.toLowerCase()) {
	iscaps = ((s.toUpperCase() === s
		   && !ev.shiftKey)
		  || (s.toLowerCase() === s
		      && ev.shiftKey));
      }
      if (iscaps && !state.iscaps) {
	if (!state.span) {
	  state.span = new Element("span", { className: "bse_capswarning" });
	  state.span.update("Check Caps Lock");
	}
	ele.parentNode.insertBefore(state.span, this.nextSibling);
      }
      else if (state.iscaps && !iscaps) {
	state.span.remove();
      }
      state.iscaps = iscaps;
    }.bindAsEventListener(ele, state));
    ele.observe("blur", function(ev, state) {
      if (state.iscaps) {
	state.span.remove();
	state.iscaps = null;
      }
    }.bindAsEventListener(ele, state));
  });
});