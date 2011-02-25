document.observe
  ("dom:loaded",
    function () {
     new Form.Observer
     ('search', 0.5, function(f) {
	var par = '_t=low&' + f.serialize();
	var updater = new Ajax.Updater(
	  'results',
	  '/cgi-bin/admin/siteusers.pl',
	  {
	    method: 'get',
	    parameters: par,
            asynchronous: true
	  });
      });
});