var api;

var msgs_shown = {};

var save_state = false;

function messages_load(msgs) {
  $("message_catalog").innerHTML = "";

  // build a tree structure, anything ending in / is a parent (of something)
  var root = [];
  var byid = {};
  var parents = {};
  for (var i = 0; i < msgs.length; ++i) {
    var msg = msgs[i];
    if (msg.id.match(/^[a-z0-9_]+\/$/)) {
      // a root node
      msg.kids = [];
      byid[msg.id] = msg;
      parents[msg.id] = msg;
      root.push(msg);
    }
    else {
      // look for a parent
      var parent_id = msg.id.replace(/[a-z0-9_]+\/?$/, "");
      var parent = parents[parent_id];
      if (!parent) {
	alert("No parent " + parent_id + " found for " + msg.id);
      }
      else {
	parent.kids.push(msg);
	if (msg.id.match(/\/$/)) {
	  msg.kids = [];
	  parents[msg.id] = msg;
	}
      }
    }
  }

  populate_msgs($("message_catalog"), root);

  api.get_base_config
  ({
     onSuccess: function(result) {
       if (result.access_control == 1) {
	 save_state = true;
	 api.get_matching_state
	 ({
	   name: "messages_open:",
	   onSuccess: function(entries) {
	     for (var i = 0; i < entries.length; ++i) {
	       var msgid = entries[i].name.replace(/^messages_open:/, "");
	       var workid = msgid.replace(/\//g, "-");
	       var ele = $("kids-"+workid);
	       if (ele) {
		 msg_hide_show(msgid, workid);
	       }
	     }
	   }
	  });
       }
     }
   });
}

function populate_msgs(ele, tree) {
  for (var i = 0; i < tree.length; ++i) {
    var msg = tree[i];
    var kid = new Element("li");
    var workid = msg.id.replace(/\//g, "-");
    kid.id = "msg-" + workid;
    if (msg.kids) {
      var a = new Element
	("a",
	{
	  href: "#"
	}
	);
      a.appendChild(document.createTextNode(msg.description));
      a.onclick = msg_hide_show.bind(this, msg.id, workid);
      kid.appendChild(a);
      var ul = new Element("ul", { id: "kids-"+workid });
      populate_msgs(ul, msg.kids);
      kid.appendChild(ul);
      msgs_shown[msg.id] = false;
    }
    else {
      kid.appendChild(document.createTextNode(msg.description + " "));
      var detail = new Element("a", { href: "#" });
      detail.update("Details");
      detail.onclick = message_detail.bind(this, msg);
      kid.appendChild(detail);
    }
    ele.appendChild(kid);
  }
}

function msg_hide_show(msgid, workid) {
  var ul = $("kids-"+workid);
  if (msgs_shown[msgid]) {
    ul.style.display = "none";
    msgs_shown[msgid] = false;
    if (save_state) api.delete_state({ name: "messages_open:"+msgid });
  }
  else {
    ul.style.display = "block";
    msgs_shown[msgid] = true;
    if (save_state) api.set_state({ name: "messages_open:"+msgid, value: 1});
  }

  return false;
}

function messages_start() {
  api = new BSEAPI;
  api.message_catalog
  ({
    onSuccess: function(messages) {
      messages_load(messages);
      $("open_all").observe("click", open_all_messages);
      $("close_all").observe("click", close_all_messages);
    }
  });
}

function open_all_messages(event) {
  for (var i in msgs_shown) {
    if (!msgs_shown[i]) {
      var workid = i.replace(/\//g, "-");
      msg_hide_show(i, workid);
    }
  }

  event.stop();
}

function close_all_messages(event) {
  for (var i in msgs_shown) {
    if (msgs_shown[i]) {
      var workid = i.replace(/\//g, "-");
      msg_hide_show(i, workid);
    }
  }

  event.stop();
}

function message_detail(msg) {
  $("message_detail_list").innerHTML = "Loading...";

  api.message_detail
  ({
     id: msg.id,
     onSuccess: function(result) {
       populate_detail(result);
     }
   });

  _open_window($("message_detail"), "Detail: "+msg.description);

  return false;
}

function defn_detail_entry(ele, base, lang, defn) {
  ele.innerHTML = "";
  var label = new Element("span", { className: "label" });
  label.update("Message: ");
  ele.appendChild(label);
  var cont_ele = new Element("span", { className: "content", id: "cont-"+lang.id });

  cont_ele.appendChild(document.createTextNode(defn.message));
  ele.appendChild(cont_ele);

  var edit_parms =
    {
      onSave: function(ele, base, lang, ipe, text) {
	api.message_save
	({
	  id: base.id,
	  language_code: lang.id,
	  message: text,
	  onSuccess: function(ele, base, lang, ipe, defn) {
	    defn_detail_entry(ele, base, lang, defn);
	    ipe.on_success();
	  }.bind(this, ele, base, lang, ipe),
	  onFailure: function(ipe, err) {
	    if (err.error_code == "FIELD") {
	      var msgs = new Array;
	      for (var i in err.errors) {
		msgs.push(err.errors[i]);
	      }
	      ipe.on_error(msgs.join("\n"));
	    }
	    else
	      ipe.on_error(err.error_code);
	  }.bind(this, ipe)
	});
      }.bind(this, ele, base, lang),
      value: defn.message
    };
  if (base.multiline != 0)
    edit_parms.rows = 5;
  new BSE.InPlaceEdit
   (
     cont_ele,
     edit_parms
   );

  ele.appendChild(document.createTextNode(" "));
  var del = new Element("a");
  del.update("Delete");
  del.onclick = remove_message.bind(this, base, lang, ele);
  ele.appendChild(del);
}

function no_detail_entry(ele, base, lang) {
  ele.innerHTML = "";
  var label = new Element("span", { className: "label" });
  label.update("Message: ");
  ele.appendChild(label);
  var cont_ele = new Element("span", { className: "content", id: "cont-"+lang.id });
  ele.addClassName("undefined");
  cont_ele.update("(undefined)");
  var edit_parms =
    {
      onSave: function(ele, base, lang, ipe, text) {
	api.message_save
	({
	  id: base.id,
	  language_code: lang.id,
	  message: text,
	  onSuccess: function(ele, base, lang, ipe, defn) {
	    defn_detail_entry(ele, base, lang, defn);
	    ipe.on_success();
	  }.bind(this, ele, base, lang, ipe),
	  onFailure: function(ipe, err) {
	    ipe.on_error(err.error_code);
	  }.bind(this, ipe)
	});
       }.bind(this, ele, base, lang)
    };
  if (base.multiline != 0)
    edit_parms.rows = 5;
  new BSE.InPlaceEdit
   (
     cont_ele,
     edit_parms
   );
  ele.appendChild(cont_ele);
}

function populate_detail(detail) {
  // build a map of defaults and definitions
  var div = $("message_detail_list");
  div.innerHTML = "";
  var base = detail.base;
  var defs = detail.defaults;
  var defns = detail.definitions;
  var langs = detail.languages;
  for (var i = 0; i < langs.length; ++i) {
    var lang = langs[i];
    var lang_ele = new Element("div", { className: "langhead" });
    lang_ele.appendChild(document.createTextNode("Language: " +lang.name));
    div.appendChild(lang_ele);
    if (defs[lang.id]) {
      var def_ele = new Element("div", { className: "default" });
      var label = new Element("span", { className: "label" });
      label.update("Default: ");
      def_ele.appendChild(label);
      var cont_ele = new Element("span", { className: "content" });
      cont_ele.appendChild(document.createTextNode(defs[lang.id].message));
      def_ele.appendChild(cont_ele);
      if (base.multiline != 0)
	def_ele.addClassName("multiline");
      div.appendChild(def_ele);
    }
    var defn = defns[lang.id];
    var defn_ele = new Element("div", { className: "definition", id: "defn-"+lang.id });
    if (base.multiline != 0)
      defn_ele.addClassName("multiline");
    if (defn)
      defn_detail_entry(defn_ele, base, lang, defn);
    else
      no_detail_entry(defn_ele, base, lang);
    div.appendChild(defn_ele);
  }
}

function remove_message(base, lang, ele) {
  if (window.confirm("Are you sure you want to delete this definition?")) {
    api.message_delete
    ({
      id: base.id,
      language_code: lang.id,
      onSuccess: function(base, lang, ele) {
	no_detail_entry(ele, base, lang);
      }.bind(this, base, lang, ele)
     });
  }
}

Event.observe(document, "dom:loaded", messages_start);