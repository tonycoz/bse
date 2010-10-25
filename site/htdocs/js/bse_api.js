// requires prototype.js for now

// true to use the File API if available
// TODO: progress reporting
// TODO: start reporting
// TODO: utf8 filenames
// TODO: quotes in filenames(?)
var bse_use_file_api = false;

var BSEAPI = Class.create
  ({
     initialize: function(parameters) {
	  if (!parameters) parameters = {};
       this.initialized = true;
       this.onException = function(obj, e) {
			    alert(e);
			    };
       this.onFailure = function(error) { alert(error.message); };
       this._load_csrfp();
       this.onConfig = parameters.onConfig;
       this._load_config();
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
     _load_config: function() {
	  this.get_base_config
	  ({
	      onSuccess:function(conf) {
		  this.conf = conf;
		  if (this.onConfig)
		      this.onConfig(conf);
	      }.bind(this),
	      onFailure: function(err) {
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
     get_base_config: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_config() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_api_request("a_config", parameters, success, failure);
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
       return "/cgi-bin/thumb.pl?image="+im.id+"&g="+geoid+"&page="+im.articleId+"&f="+encodeURIComponent(im.image);
     },
     can_drag_and_drop: function() {
       // hopefully they're implemented at the same time
       return bse_use_file_api && window.FileReader != null;
     },
     make_drop_zone: function(options) {
       options.element.addEventListener
       (
	 "dragenter",
	 function(options, e) {
	   e.stopPropagation();
	   e.preventDefault();
	 }.bind(this, options),
	 false
       );
       options.element.addEventListener
       (
	 "dragover",
	 function(options, e) {
	   e.stopPropagation();
	   e.preventDefault();
	 }.bind(this, options),
	 false
       );
       options.element.addEventListener
       (
	 "drop",
	 function(options, e) {
	   e.stopPropagation();
	   e.preventDefault();

	   options.onDrop(e.dataTransfer.files);
	 }.bind(this, options),
	 false
       );
     },
     // parameters:
     //  image - file input element (required)
     //  id - owner article of the new image (required)
     //  name - name of the image to add (default: "")
     //  alt - alt text for the image (default: "")
     //  url - url for the image (default: "")
     //  storage - storage for the image (default: auto)
     //  onSuccess: called on success in adding the image, with the image object
     //    (required)
     //  onFailure: called on failure (optional)
     //  onStart: called when the image upload starts (optional)
     //  onComplete: called when the image upload is complete (success
     //    or failure) (optional)
     //  onProgress: called occasionally during the image upload with
     //    the approximate amount sent and the total to be sent (optional)
     add_image_file: function(parameters) {
	  parameters._csrfp = this._csrfp.admin_add_image;
       var success = parameters.onSuccess;
       parameters.onSuccess = function(success, result) {
	 success(result.image);
       }.bind(this, success);
	  this._do_complex_request("/cgi-bin/admin/add.pl", "addimg", parameters);
      },
     save_image_file: function(parameters) {
       parameters._csrfp = this._csrfp.admin_save_image;
       var success = parameters.onSuccess;
       parameters.onSuccess = function(success, result) {
	 success(result.image);
       }.bind(this, success);
       this._do_complex_request("/cgi-bin/admin/add.pl", "a_save_image", parameters);
     },
     remove_image_file: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("remove_image_file() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var im = parameters.image;
       if (!im) this._badparm("remove_image_file() missing image parameter");
       this._do_add_request
         (
	 "removeimg_"+im.id,
	 {
	   id: im.articleId
	 },
	 success, failure
	 );
     },
     images_set_order: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("remove_image_file() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var id = parameters.id;
       if (!id) this._badparm("images_set_order() missing id parameter");
       var order = parameters.order.join(",");
       this._do_add_request("a_order_images", { id: id, order: order }, success, failure);
     },

     // Message catalog functions
     message_catalog: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("remove_image_file() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       this._do_request
	 (
	 "/cgi-bin/admin/messages.pl", "a_catalog", { },
	 function(success, resp) {
	   success(resp.messages);
	 }.bind(this, success),
	 failure
	 );
     },
     message_detail: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("message_detail() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var id = parameters.id;
       if (id == null) this._badparm("message_detail() missing id parameter");
       this._do_request
	 (
	   "/cgi-bin/admin/messages.pl", "a_detail", { id: id }, success, failure
	 );
     },
     // requires id, language_code, message
     message_save: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("message_save() missing onSuccess parameter");
       var my_success = function(success, resp) {
	 success(resp.definition);
       }.bind(this, success);
       delete parameters.success;
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.failure;
       this._do_request("/cgi-bin/admin/messages.pl", "a_save", parameters,
			my_success, failure);
     },
     // requires id, language_code
     message_delete: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("message_delete() missing onSuccess parameter");
       delete parameters.success;
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.failure;
       this._do_request("/cgi-bin/admin/messages.pl", "a_delete", parameters,
			success, failure);
     },

     // requires name, value
     set_state: function(parameters) {
       var success = parameters.onSuccess || function() {};
       var failure = parameters.onFailure || this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_request("/cgi-bin/admin/menu.pl", "a_set_state", parameters, success, failure);
     },
     // requires name
     get_state: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_state() missing onSuccess parameter");
       var my_success = function(success, result) {
	 success(result.value);
       }.bind(this, success);
       var failure = parameters.onFailure || this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_request("/cgi-bin/admin/menu.pl", "a_get_state", parameters, my_success, failure);
     },
     // requires name
     delete_state: function(parameters) {
       var success = parameters.onSuccess || function() {};
       var failure = parameters.onFailure || this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_request("/cgi-bin/admin/menu.pl", "a_delete_state", parameters, success, failure);
     },

     // requires name, a prefix for the state entries we want
     get_matching_state: function(parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("get_matching_state() missing onSuccess parameter");
       var my_success = function(success, result) {
	 success(result.entries);
       }.bind(this, success);
       var failure = parameters.onFailure || this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_request("/cgi-bin/admin/menu.pl", "a_get_matching_state", parameters, my_success, failure);

     },

     // requires name, a prefix for the state entries we want
     delete_matching_state: function(parameters) {
       var success = parameters.onSuccess || function() {};
       var failure = parameters.onFailure || this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       this._do_request("/cgi-bin/admin/menu.pl", "a_delete_matching_state", parameters, success, failure);

     },

     _progress_handler: function(parms) {
	  if (parms.finished) return;
       this.get_file_progress(
       {
	 _upload: parms.up_id,
	 onSuccess: function(parms, prog) {
	   if (!parms.finished) {
	     if (prog) {
		 if (prog.total)
               parms.total = prog.total;
	       parms.progress(prog);
	     }
	     parms.updates += 1;
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
     _add_complex_item: function(form, key, val, clone) {
       if (typeof(val) == "string" || typeof(val) == "number") {
	 form.appendChild(this._hidden(key, val));
       }
       else if (typeof(val) == "object") {
	 if (val.constructor == Array) {
	   for (var i = 0; i < val.length; ++i) {
	     this._add_complex_item(form, key, val[i], clone);
	   }
	 }
	 else {
	   // presumed to be a file field
	   if (clone) {
	     var cloned = val.cloneNode(true);
	     val.parentNode.insertBefore(cloned, val);
	   }
           val.name = key;
	   form.appendChild(val);
	 }
       }
     },
     _populate_complex_form: function(form, req_parms, clone) {
       for (var key in req_parms) {
         this._add_complex_item(form, key, req_parms[key], clone);
       }
     },
     // perform a request through an iframe
     // parameters can contain:
     // onSuccess: callback called on successful processs
     // onFailure: called on failed processing
     // onStart: called when the form is submitted
     // onProgress: called occasionally with submission progres info
     // onComplete: called on completion (before onSuccess/onFailure)
     // clone: if true, clone any file objects supplied
     //
     // all other parameters are treated as form fields.
     // if a value is an array, it is treated as multiple values for
     // that field
     //
     // Bugs: should fallback to Ajax if there are no form fields
     _do_complex_request: function(url, action, parameters) {
       var success = parameters.onSuccess;
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       var on_complete = parameters.onComplete;
       var on_start = parameters.onStart;
       var on_progress = parameters.onProgress;
       var clone = parameters.clone;

       delete parameters.onSuccess;
       delete parameters.onFailure;
       delete parameters.onComplete;
       delete parameters.onProgress;
       delete parameters.onStart;
       delete parameters.clone;

       // stuff we use in the callbacks
       var parms =
	 {
	 success: success,
	 failure: failure,
	 start: on_start,
	 progress: on_progress,
	 complete: on_complete,
	 // track the number of progress updates done
	 updates: 0,
	 finished: 0
	 };

       parms.up_id = this._new_upload_id();
       if (url.match(/\?/))
	 url += "&";
       else
	 url += "?";
       url += "_upload=" + parms.up_id;

       if (window.FileReader && bse_use_file_api) {
	 if (this._do_complex_file_api(url, action, parms, parameters))
	   return;
       }

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
	 action: url,
	 enctype: "multipart/form-data",
	 // the following for IE
	 encoding: "multipart/form-data",
	 id: "bseform"+parms.up_id,
	 target: "bseiframe"+parms.up_id
       });
       parms.form = form;
       form.style.display = "none";
       // _upload must come before anything large
       //form.appendChild(this._hidden("_upload", parms.up_id));
       form.appendChild(this._hidden("_",1));
       this._populate_complex_form(form, parameters, clone);
       // trigger BSE's alternative JSON return handling
       form.appendChild(this._hidden("_", 1));
       form.appendChild(this._hidden(action, 1));

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
         if (parms.progress != null && parms.total != null)
	   parms.progress({ done: parms.total, total: parms.total});
	 if (parms.complete != null)
	   parms.complete();
	 parms.finished = 1;
	 if (data != null) {
	   if (data.success != null && data.success != 0) {
	     parms.success(data);
	   }
	   else {
	     parms.failure(data);
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

       if (on_start != null)
	 on_start();

       if (on_progress != null) {
	 parms.timeout = window.setTimeout ( this._progress_handler.bind(this, parms), 200 );
       }

       form.submit();
     },
     // flatten the parameters
     _flat_parms: function(flat, key, val) {
       if (typeof(val) == "string" || typeof(val) == "number") {
	 flat.push([ key, val, false ]);
       }
       else if (typeof(val) == "object") {
	 if (val.constructor == Array) {
	   for (var i = 0; i < val.length; ++i) {
	     this._flat_parms(flat, key, val[i]);
	   }
	 }
	 else if (val.constructor == File) {
	   // File object from drag and drop
	   flat.push([key, val, true]);
	 }
	 else {
	   // this should handle File objects, not just elements
	   // or perhaps data transfer objects
	   // push the individual files if there's multiple
	   for (var i = 0; i < val.files.length; ++i) {
	     flat.push([key, val.files[i], true]);
	   }
	 }
       }
     },
     _build_api_req_data: function(state) {
       while (state.index < state.flat.length) {
	 var entry = state.flat[state.index];
	 if (entry[2]) {
	   // file object
	   var fr  = new FileReader;
	   fr.addEventListener
	   ("loadend", function(state, fr, event) {
   	      var entry = state.flat[state.index];
	      state.req_data += "--" + state.sep + "\r\n";
	      // TODO: filenames with quotes
	      state.fileoffsets.push([ state.req_data.length, entry[1].fileName]);
	      state.req_data += "Content-Disposition: form-data; name=\"" + entry[0] + "\"; filename=\"" + this._encode_utf8(entry[1].fileName) + "\"\r\n\r\n";
	      state.req_data += event.target.result + "\r\n";
	      ++state.index;
	      this._build_api_req_data(state);
	    }.bind(this, state, fr), false);
	   fr.readAsBinaryString(entry[1]);
	   return;
	 }
	 else {
	   // just plain data
	   state.req_data += "--" + state.sep;
	   state.req_data += "Content-Disposition: form-data; name=\"" + entry[0] + "\"\r\n\r\n";
	   state.req_data += this._encode_utf8(entry[1]) + "\r\n";
	   ++state.index;
	 }
       }

       // everything should be state.req_data now
       state.req_data += "--"  + state.sep + "--\r\n";

       state.xhr = new XMLHttpRequest();
       if (state.start)
	 state.start();
       if (state.progress && state.xhr.upload) {
	 state.xhr.upload.addEventListener
	   (
	   "progress",
	   function(state, evt) {
	     if (evt.lengthComputable) {
	       var filename;
	       for (var i = 0; i < state.fileoffsets.length; ++i) {
		 if (evt.loaded > state.fileoffsets[i][0])
		   filename = state.fileoffsets[i][1];
	       }
	       state.last_filename = filename;
	       state.progress
	       (
		 {
		   done: evt.loaded,
		   total: evt.total,
		   filename: filename,
		   complete: 0
		 }
	       );
	     }
	   }.bind(this, state),
	   false
	   );
	 state.xhr.upload.addEventListener
	   (
	   "load",
	   function(state, evt) {
	     if (evt.lengthComputable) {
	       state.progress
	       (
		 {
		   done: evt.total,
		   total: evt.total,
		   filename: state.last_filename,
		   complete: 1
		 }
	       );
	     }
	   }.bind(this, state),
	   false
	   );
       }
       state.xhr.open("POST", state.url, true);
       state.xhr.onreadystatechange = function(state, event) {
	 if (state.xhr.readyState == 4) {
	   if (state.complete)
	     state.complete();
	   if (state.xhr.status == 200) {
	     var data;
	     try {
	       data = state.xhr.responseText.evalJSON(false);
	     } catch (e) {
	       state.failure(this._wrap_nojson_failure(state.xhr));
	       return;
	     }

	     if (data.success != null && data.success != 0 ) {
	       state.success(data);
	     }
	     else {
	       state.failure(this._wrap_json_failure({ responseJSON: data}));
	     }
	   }
	   else {
	     state.failure(this._wrap_req_failure(state.xhr));
	   }
	 }
       }.bind(this, state);
       state.xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary="+state.sep);
       state.xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
       state.xhr.sendAsBinary(state.req_data);
     },
     // use the HTML5 file API to perform the upload
     _do_complex_file_api: function(url, action, state, req_parms) {
       state.url = url;
       //state.url = "/cgi-bin/dump.pl";
       if (action != null)
	 req_parms[action] = 1;
       state.sep = "x" + state.up_id + "x";
       state.fileoffsets = new Array;

       // flatten the request parameters
       var flat = new Array;
       for (var key in req_parms) {
         this._flat_parms(flat, key, req_parms[key]);
       }
       state.index = 0;
       state.flat = flat;
       state.req_data = '';
       this._build_api_req_data(state);
       // the rest happens elsewhere

       return true;
     },
     // in the future this might call a proxy
     _do_add_request: function(action, other_parms, success, failure) {
       this._do_request("/cgi-bin/admin/add.pl", action, other_parms, success, failure);
     },
     _do_api_request: function(action, other_parms, success, failure) {
       this._do_request("/cgi-bin/api.pl", action, other_parms, success, failure);
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
     _encode_utf8: function(str) {
       return unescape(encodeURIComponent(str));
     },
     // we request these names on startup, on login
     // and occasionally otherwise, to avoid them going stale
     _csrfp_names:
       [
	 "admin_add_image",
	 "admin_save_image"
       ],
     _upload_id: 0
   });

