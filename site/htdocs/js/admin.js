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
});