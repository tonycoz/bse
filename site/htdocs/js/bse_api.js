// requires prototype.js for now

var BSEAPI = Class.create
  ({
     initialize: function(domain) {
       this.initialized = true;
       this.onException = function(obj, e) {
			    alert(e);
			    };
       this.onFailure = function(error) { alert(error.message); };
       this._load_csrfp();
     },
     _load_csrfp: function () {
       this.get_csrfp
       ({
	 id: -1,
	  name: this._csrfp_names,
	 onSuccess: function(csrfp) {
	   this._csrfp = csrfp;
	   window.setTimeout(this._load_csrfp.bind(this), 600000);
	 }.bind(this),
	 onFailure: function() {
	   // ignore this
	   this._csrfp = null;
	 }
       });
     },
     // logon to the server
     // logon - logon name of user
     // password - password of user
     // onSuccess - called on successful logon (no parameters)
     // onFailure - called with an error object on failure.
     logon: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("logon() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       if (parameters.logon == null)
	 this._badparm("logon() Missing logon parameter");
       if (parameters.password == null)
	 this._badparm("logon() Missing password parameter");
       new Ajax.Request('/cgi-bin/admin/logon.pl',
       {
	 parameters: {
	   a_logon: 1,
	   logon: parameters.logon,
	   password: parameters.password
	 },
	 onSuccess: function (success, failure, resp) {
	   if (resp.responseJSON) {
             if(resp.responseJSON.success != 0) {
	       this._load_csrfp();
	       success(resp.responseJSON.user);
             }
             else {
	       failure(this._wrap_json_failure(resp), resp);
             }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function (failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     userinfo: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("logon() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       new Ajax.Request('/cgi-bin/admin/logon.pl',
       {
	 parameters: {
	   a_userinfo: 1
	 },
	 onSuccess: function (success, failure, resp) {
	   if (resp.responseJSON) {
             if(resp.responseJSON.success != 0) {
	       success(resp.responseJSON);
             }
             else {
	       failure(this._wrap_json_failure(resp), resp);
             }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function (failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     logoff: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("logon() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       new Ajax.Request('/cgi-bin/admin/logon.pl',
       {
	 parameters: {
	   a_logoff: 1
	 },
	 onSuccess: function (success, failure, resp) {
	   if (resp.responseJSON) {
             if(resp.responseJSON.success != 0) {
	       success();
             }
             else {
	       failure(this._wrap_json_failure(resp), resp);
             }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function (failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     // fetch a tree of articles;
     // id - parent of tree to fetch
     // depth - optional depth of tree to fetch (default is large)
     // onSuccess - called with tree on success
     // onFailure - called with error object on failure
     tree: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var req_parms = { id: -1, a_tree: 1 };
       if (parameters.id)
	 req_parms.id = parameters.id;
       if (parameters.depth)
	 req_parms.depth = parameters.depth;
       new Ajax.Request('/cgi-bin/admin/add.pl',
       {
	 parameters: req_parms,
	 onSuccess: function(success, failure, resp) {
	   if (resp.responseJSON) {
	     if (resp.responseJSON.success != 0) {
	       success(resp.responseJSON.articles);
	     }
	     else {
	       failure(this._wrap_json_failure(resp), resp);
	     }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function(failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     article: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       if (parameters.id == null)
	 this._badparm("article() missing id parameter");
       var req_parms = { a_article: 1, id: parameters.id };
       new Ajax.Request('/cgi-bin/admin/add.pl',
       {
	 parameters: req_parms,
	 onSuccess: function(success, failure, resp) {
	   if (resp.responseJSON) {
	     if (resp.responseJSON.success != 0) {
	       success(resp.responseJSON.article);
	     }
	     else {
	       failure(this._wrap_json_failure(resp), resp);
	     }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function(failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     // create a new article, accepts all article fields except id
     new_article: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       if (parameters.title == null)
	 this._badparm("new_article() missing title parameter");
       if (parameters.parentid == null)
	 this._badparm("new_article() missing parentid parameter");
       if (parameters.id != null)
	 this._badparm("new_article() can't accept an id parameter");
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_add_request("save", parameters,
         function(success, resp) {
	   success(resp.article);
	 }.bind(this, success),
	 failure);
     },
     save_article: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       if (parameters.id == null)
	 this._badparm("save_article() missing id parameter");
       if (parameters.lastModified == null)
	 this._badparm("save_article() missing lastModified parameter");
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_add_request("save", parameters,
	 function(success, result) {
	   success(result.article);
	 }.bind(this, success),
	 failure);
     },
     get_config: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_config() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       if (parameters.id == null && parameters.parentid == null)
         this._badparm("get_config() missing both id and parentid");
       this._do_add_request("a_config", parameters, success, failure);
     },
     get_csrfp: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_csrfp() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       if (parameters.id == null && parameters.id == null)
         this._badparm("get_csrfp() missing both id and parentid");
       this._do_add_request("a_csrfp", parameters,
	function(success, result) {
	  success(result.tokens);
	}.bind(this, success),
	failure);
     },
     get_file_progress: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_file_progress() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       if (parameters._upload == null)
         this._badparm("get_file_progress() missing _upload");
       this._do_request("/cgi-bin/fileprogress.pl", null, parameters,
	function(success, result) {
	  success(result.progress);
	}.bind(this, success),
	failure);
     },
     thumb_link: function(im, geoid) {
       return "/cgi-bin/admin/add.pl?a_thumb=1&im="+im.id+"&g="+geoid+"&id="+im.articleId;
     },
     // parameters:
     //  file - file input element (required)
     //  name - name of the image to add (required)
     //  article_id - owner article of the new image (required)
     //  alt - alt text for the image (default: "")
     //  url - url for the image (default: "")
     //  storage - storage for the image (default: auto)
     add_image_file: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var file = parameters.file;
       if (file == null) this._badparm("tree() missing file parameter");

       // stuff we use in the callbacks
       var parms =
	 {
	   success: success,
	   failure: failure,
	   progress: parameters.onProgress,
	   complete: parameters.onComplete,
	   // track the number of progress updates done
	   updates: 0,
	   finished: 0
	 };

       parms.up_id = this._new_upload_id();

       // setup the iframe
       parms.ifr = new Element("iframe", {
	 src: "about:blank",
	 id: "bseiframe"+parms.up_id,
	 name: "bseiframe"+parms.up_id,
	 width: 400,
	 height: 100
       });
       parms.ifr.style.display = "none";

       // setup the form
       var form = new Element
	 ("form",
	 {
	   method: "post",
	   action: "/cgi-bin/admin/add.pl",
	   enctype: "multipart/form-data",
	   // the following for IE
	   encoding: "multipart/form-data",
	   id: "bseform"+parms.up_id,
	   target: "bseiframe"+parms.up_id
	 });
       parms.form = form;
       form.style.display = "none";
       form.appendChild(this._hidden("_upload", parms.up_id));
       if (parameters.clone) {
	 var cloned = file.cloneNode(true);
	 file.parentNode.insertBefore(cloned, file);
       }
       file.name = "image";
       form.appendChild(file);
       form.appendChild(this._hidden("id", parameters.article_id));
       // trigger BSE's alternative JSON return handling
       form.appendChild(this._hidden("_", 1));
       if (parameters.name != null)
	 form.appendChild(this._hidden("name", parameters.name));
       if (parameters.alt != null)
         form.appendChild(this._hidden("alt", parameters.alt));
       if (parameters.url != null)
	 form.appendChild(this._hidden("url", parameters.url));
       if (parameters.storage != null)
	 form.appendChild(this._hidden("storage", parameters.storage));
       form.appendChild(this._hidden("_csrfp", this._csrfp.admin_add_image));
       form.appendChild(this._hidden("addimg", 1));

       document.body.appendChild(parms.ifr);
       document.body.appendChild(form);
       var onLoad = function(parms) {
	 // we should get json back in the body
         var ifr = parms.ifr;
	 var form = parms.form;
	 var text = Try.these(
	   function(ifr) {
	     var text = ifr.contentDocument.body.textContent;
	     ifr.contentDocument.close();
	     return text;
	   }.bind(this, ifr),
	   function(ifr) {
	     var text = ifr.contentWindow.document.body.innerText;
	     ifr.contentWindow.document.close();
	     return text;
	   }.bind(this, ifr)
	 );
	 var data;
	 eval("data = " + text + ";");
	 document.body.removeChild(ifr);
	 document.body.removeChild(form);
	 if (parms.complete != null)
	   parms.complete();
	 parms.finished = 1;
	 if (data != null) {
	   if (data.success != null && data.success != 0) {
	     parms.success(data.image);
	   }
	   else {
	     parms.failure(this._wrap_json_failure(data));
	   }
	 }
	 else {
	   parms.failure(this._wrap_req_failure({statusText: "Unknown"}));
	 }
       }.bind(this, parms);
       if (window.attachEvent) {
	 parms.ifr.attachEvent("onload", onLoad);
       }
       else {
	 parms.ifr.addEventListener("load", onLoad, false);
       }

       if (parameters.onStart != null)
	 parameters.onStart(file.value);

       if (parameters.onProgress != null) {
	 parms.timeout = window.setTimeout ( this._progress_handler.bind(this, parms), 200 );
       }

       form.submit();
     },
     _progress_handler: function(parms) {
       this.get_file_progress(
       {
	 _upload: parms.up_id,
	 onSuccess: function(parms, prog) {
	   if (prog.length) {
	     parms.progress(prog[0], prog[1]);
	   }
	   parms.updates += 1;
	   if (!parms.finished) {
             parms.timeout = window.setTimeout
	       (this._progress_handler.bind(this, parms),
		 parms.updates > 5 ? 6000 : 1500);
	   }
	 }.bind(this, parms)
       });
     },
     _hidden: function(name, value) {
       var hidden = document.createElement("input");
       hidden.type = "hidden";
       hidden.name = name;
       hidden.value = value;

       return hidden;
     },
     _wrap_json_failure: function(resp) {
       return resp.responseJSON;
     },
     _wrap_nojson_failure: function(resp) {
       return {
	   success: 0,
	   message: "Unexpected non-JSON response from server",
	   errors: {},
	   error_code: "NOTJSON"
	 };
     },
     _wrap_req_failure: function(resp) {
       return {
	 success: 0,
	 message: "Server error requesing content: " + resp.statusText,
	 errors: {},
	 error_code: "SERVFAIL"
       };
     },
     _badparm: function(msg) {
       this.onException(msg);
     },
     // in the future this might call a proxy
     _do_add_request: function(action, other_parms, success, failure) {
       this._do_request("/cgi-bin/admin/add.pl", action, other_parms, success, failure);
     },
     _do_request: function(url, action, other_parms, success, failure) {
       if (action != null)
         other_parms[action] = 1;
       new Ajax.Request(url,
       {
	 parameters: other_parms,
	 onSuccess: function (success, failure, resp) {
	   if (resp.responseJSON) {
	     if (resp.responseJSON.success != null && resp.responseJSON.success != 0) {
	       success(resp.responseJSON);
	     }
	     else {
	       failure(this._wrap_json_failure(resp), resp);
	     }
	   }
	   else {
	     failure(this._wrap_nojson_failure(resp), resp);
	   }
	 }.bind(this, success, failure),
	 onFailure: function(failure, resp) {
	   failure(this._wrap_req_failure(resp), resp);
	 }.bind(this, failure),
	 onException: this.onException
       });
     },
     _new_upload_id: function () {
       this._upload_id += 1;
       return new Date().valueOf() + "_" + this._upload_id;
     },
     // we request these names on startup, on login
     // and occasionally otherwise, to avoid them going stale
     _csrfp_names: [ "admin_add_image" ],
     _upload_id: 0
   });
