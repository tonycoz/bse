var art_by_id = {};
function populate_tree(div, articles) {
  for (var i = 0; i < articles.length; ++i) {
    var art = articles[i];
    art_by_id[art.id] = art;
    var kid = document.createElement("div");
    var text = document.createTextNode(art.title);
    var a = document.createElement("a");
    a.href = "#";
    a.appendChild(text);
    a.id = "title" + art.id;
    a.onclick = load_article.bind(this, art.id); //"return load_article(" + art.id + ");";
    kid.appendChild(a);
    div.appendChild(kid);
    if (art.children && art.children.length) {
      populate_tree(kid, art.children);
    }
  }
}
function error_message(text) {
  alert(text);
}

function success_message(text) {
  alert(text);
}

function set_current_user(user) {
  $("user").innerHTML = "";
  $("user").appendChild(document.createTextNode(user.name));
  $("usertop").style.display = "block";
}

var api = new BSEAPI();
function do_logon() {
  if ($('logon').value == '' || $('password').value == '') {
    error_message("Please enter a logon and password");
    return false;
  }
  $("logonf").style.display = "none";
  set_busy();
  api.logon({
    logon: $('logon').value,
    password: $('password').value,
    onSuccess: function(user) {
      $('password').value = '';
      set_current_user(user);
      unset_busy();
      post_logon();
    },
    onFailure: function(error) {
      if (error.error_code == "INVALID") {
        alert("Invalid logon or password");
        $('password').value = '';
        $("logonf").style.display = "block";
      }
      else {
        alert(error.message);
      }
    }
  });

  return false;
}
function ask_logon() {
  $("logonf").style.display = "block";
}

function do_logoff() {
  set_busy();
  api.logoff({
    onSuccess: function() {
      unset_busy();
      ask_logon();
    },
    onFailure: function(result) {
      unset_busy();
      alert($result.message);
    }
  });
  return false;
}

var art_tree;
function load_tree() {
  api.tree({
    onSuccess: function(articles) {
      $('treetop').style.display = "block";
      $('tree').innerHTML = '';
      art_by_id = {};
      populate_tree($('tree'), articles);
      art_tree = articles;
    },
    onFailure: function(error) {
      if (error.error_code == "LOGON") {
        ask_logon();
      }
      else {
        alert(error.message);
      }
    }
  });
  return false;
}
function load_article(id) {
  api.article({
    id: id,
    onSuccess: function(article) {
      $("article").style.display = "block";
      edit_article(article);
    },
    onFailure: function(error) {
      alert(error.message);
    }
  });
  return false;
}

var last_article;
function edit_article(article) {
  last_article = article;
  $("artcontent").innerHTML = "";
  var f = document.createElement("form");
  f.id = "article_form";
  var title_div = document.createElement("div");
  title_div.appendChild(document.createTextNode("Title: "));
  var inp = document.createElement("input");
  inp.type="text";
  inp.id = "title";
  inp.value = article.title;
  title_div.appendChild(inp);
  f.appendChild(title_div);
  $("artcontent").appendChild(f);

  // get the article template list
  api.get_config({
    id: article.id,
    onSuccess: function(article, config) {
      var f = $("article_form");
      var template_div = document.createElement("div");
      template_div.appendChild(document.createTextNode("Template:"));
      var sel = document.createElement("select");
      sel.id = "template";
      var templates = config.templates;
      for (i = 0; i < templates.length; ++i) {
        var template = templates[i];
        var display = template.name;
        if (template.name != template.description)
          display += " - " + template.description;
        sel.options[sel.options.length] = new Option(display, template.name, template.name == article.template, template.name == article.template);
      }
      template_div.appendChild(sel);
      f.appendChild(template_div);
      var sib_ids;
      if (article.parentid == -1) {
        sib_ids = art_tree;
      }
      else {
        sib_ids = art_by_id[article.parentid].allkids;
      }
      if (sib_ids) {
        var odiv = document.createElement("div");
        odiv.appendChild(document.createTextNode("After:"));
        var osel = document.createElement("select");
        osel.id = "_after";
        osel.options[0] = new Option("(no change)", "");
        osel.options[1] = new Option("(beginning)", "0");
        for (var i = 0; i < sib_ids.length; ++i) {
          sib = art_by_id[sib_ids[i].id];
          if (sib.id != article.id) {
            var name = sib.title + " (" + sib.id + ")";
            if (sib_ids[i].step_id != null)
              name += " (stepkid)";
            osel.options[osel.options.length]
              = new Option(name, sib.id);
          }
        }
        odiv.appendChild(osel);
        f.appendChild(odiv);
      }
      f.onsubmit = save_article.bind(this, article.id, inp);
      var sub = document.createElement("input");
      sub.type="submit";
      sub.value="Save";
      f.appendChild(sub);
    }.bind(this, article)
  });
  //load_csrfp(article.id);

  var imgs_div = $("imagelist");
  imgs_div.innerHTML = "";
  var ims = article.images;
  for (var i = 0; i < ims.length; ++i) {
    var img_div = document.createElement("div");
    img_div.id = "imgdiv" + ims[i].id;
    var img_img = document.createElement("img");
    img_img.id = "img" + ims[i].id;
    img_img.src = api.thumb_link(ims[i], "editor");
    img_div.appendChild(img_img);
    imgs_div.appendChild(img_div);
  }

  if (api.can_drag_and_drop()) {
    var dz = new Element("div", { id: "dropzone" });
    dz.appendChild(document.createTextNode("Drop!"));
    imgs_div.appendChild(dz);
    api.make_drop_zone
    (
      {
        element: dz,
        onDrop: function(files) {
	  _send_drop_files({files: files, index: 0});
        }
      }
    );
  }
  //$("image_article_id").value = article.id;
}

function _send_drop_files(state) {
  api.add_image_file({
    image: state.files[state.index],
    name: "",
    id: last_article.id,
    onSuccess: function(state) {
      ++state.index;
      if (state.index < state.files.length) {
	_send_drop_files(state);
      }
      else {
	alert("Files sent");
      }
    }.bind(this, state),
    onFailure: function() {
      alert("upload error");
    },
    onStart: _progress_start,
    onComplete: function(state) {
      if (state.index == state.files.length - 1)
	_progress_complete();
    }.bind(this, state),
    onProgress: _progress_progress
    });
}

function save_article(id, inp) {
  if (inp.value == "") {
    alert("Title cannot be empty");
  }
  else {
    var save_parms = {
      id: id,
      title: inp.value,
      template: $("template").value,
      lastModified: last_article.lastModified,
      onSuccess: function(art) {
        $("title"+id).innerHTML = "";
        $("title"+id).appendChild(document.createTextNode(art.title));
        last_article = art;
        $("artcontent").innerHTML = "";
        alert("Changes saved");
      },
      onFailure: function(e) {
        alert(e.message);
      }
      };
    if ($("_after").value != "") {
      save_parms._after = $("_after").value;
    }
    api.save_article(save_parms);
  }
  return false;
}

function set_busy() {
  $("busy").style.display = "block";
}

function unset_busy() {
  $("busy").style.display = "none";
}

var prog_timeout;
var prog_filename;
var prog_id;
var uploading = 0;
var prog_updates;
function xxdo_image_upload() {
  uploading = 1;
  prog_filename =   $("imagefile").value;
  prog_id = $("image_upload_id").value;
  prog_updates = 0;

  $("imageaddform").style.display = "none";
  $("imageprog").innerHTML = "--";
  $("imageprogwrap").style.display = "block";
  prog_timeout = window.setTimeout("update_progress()", 200);
}

function _progress_start() {
  $("imageprogwrap").style.display = "block";
  $("imageprog").innerHTML = "--";
}

function _progress_complete() {
  window.setTimeout("hide_progress()", 5000);
}

function _progress_progress(prog) {
  var text = "";
  if (prog.total)
    text = text + (Math.round(prog.done / prog.total * 1000) / 10) + "%";
  if (prog.filename)
    text = text + " - " + prog.filename;
  $("imageprog").innerHTML = text;
}

function do_image_upload() {
  var file = $("imagefile");
  var name = $("imagename").value;
  api.add_image_file({
    image: file,
    name: name,
    id: last_article.id,
    clone: true,
    onSuccess: function () {
      alert("upload successful");
    },
    onFailure: function () {
      alert("upload error");
    },
    onStart: _progress_start,
    onComplete: _progress_complete,
    onProgress: _progress_progress
  });
  return false;
}

function img_done() {
  uploading = 0;
  $("imagefile").value = "";
  $("imageaddform").style.display = "block";
  window.clearTimeout(prog_timeout);
  window.setTimeout("hide_progress()", 2000);
}

function hide_progress() {
  $("imageprogwrap").style.display = "none";
}

function update_progress() {
  api.get_file_progress({
    _upload: prog_id,
    filename: prog_filename,
    onSuccess: function(prog) {
      if (prog.length) {
        $("imageprog").innerHTML = Math.round(prog[0] / prog[1] * 1000) / 10;
      }
      else {
        $("imageprog").innerHTML = "--";
      }
      prog_updates += 1;
      if (uploading != 0)
        prog_timeout = window.setTimeout("update_progress()", prog_updates > 5 ? 6000 : 1500);
    }
  });
}

function load_csrfp(id) {
  api.get_csrfp({
    name: [ "admin_add_image" ],
    id: id,
    onSuccess: function(tokens) {
      $("image_csrfp").value = tokens.admin_add_image;
    },
    onFailure: function(result) {
      error_message(result.message);
    }
  });
}

function set_progress_markers() {
  //$("image_upload_id").value = Math.random();
}

function post_logon() {
  load_tree();
  set_progress_markers();
}

function startup() {
  api.userinfo({
    onSuccess: function(json) {
      if (json.access_control != 0 && json.user != null) {
        set_current_user(json.user);
      }

      if (json.access_control == 0 || json.user != null) {
        $("logonf").style.display = "none";
        post_logon();
      }
      else {
        ask_logon();
      }
    }
  });
}

document.observe("dom:loaded", function () { startup(); });

function seltab(which) {
  $("article").className = "tab" + which;
  return false;
}
