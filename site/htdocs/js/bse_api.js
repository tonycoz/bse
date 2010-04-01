// requires prototype.js for now

var BSEAPI = Class.create
  ({
     initialize: function(domain) {
       this.initialized = true;
       this.onException = function(obj, e) {
			    alert(e);
			    };
       this.onFailure = function(error) { alert(error.message); };
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
       if (!success) this._badparm("tree() missing onSuccess parameter");
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
       if (!success) this._badparm("tree() missing onSuccess parameter");
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
       if (!success) this._badparm("tree() missing onSuccess parameter");
       var failure = parameters.onFailure;
       if (!failure) failure = this.onFailure;
       delete parameters.onSuccess;
       delete parameters.onFailure;
       if (parameters._upload == null)
         this._badparm("get_file_progress() missing _upload");
       if (parameters.filename == null)
         this._badparm("get_file_progress() missing filename");
       this._do_request("/cgi-bin/fileprogress.pl", "a_csrfp", parameters,
	function(success, result) {
	  success(result.progress);
	}.bind(this, success),
	failure);
     },
     thumb_link: function(im, geoid) {
       return "/cgi-bin/admin/add.pl?a_thumb=1&im="+im.id+"&g="+geoid+"&id="+im.articleId;
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
     }
   });
