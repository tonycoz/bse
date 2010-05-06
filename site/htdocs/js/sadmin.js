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

  _populate_images(article.images);
  //$("image_article_id").value = article.id;
}

function _fill_one_image(div, im) {
  div.className = "animage";
  div.id = "imgdiv" + im.id;
  var img_img = document.createElement("img");
  img_img.id = "img" + im.id;
  img_img.src = api.thumb_link(im, "sadmingall");
  div.appendChild(img_img);

  var edit = new Element("a", { href: "#", className: "img_edit" });
  edit.update("Edit");
  edit.onclick = _start_edit_image.bind(this, im);
  div.appendChild(edit);

  var del = new Element("a", { href: "#", className: "img_del" });
  del.update("Delete");
  del.onclick = _start_delete_image.bind(this, im);
  div.appendChild(del);
}

function _populate_images(ims) {
  var imgs_div = $("imagelist");
  imgs_div.innerHTML = "";
  for (var i = 0; i < ims.length; ++i) {
    var img_div = document.createElement("div");
    _fill_one_image(img_div, ims[i]);

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
	  for (var i = 0; i < files.length; ++i) {
	    _send_drop_file(files[i]);
	  }
        }
      }
    );
  }
  _make_images_orderable();
}

function _make_images_orderable() {
  Sortable.create
  ("imagelist",
   {
     tag: "div",
     only: "animage",
     format: /^imgdiv(\d+)$/,
     overlap: "horizontal",
     constraint: "horizontal",
     onUpdate: function () {
       api.images_set_order
       (
	 {
	   id: last_article.id,
	   order: Sortable.sequence("imagelist"),
	   onSuccess: function() {}
	 }
       );
     }
   }
  );
}

var active_uploads = 0;
var queued_uploads = new Array;
function _send_drop_file(file) {
  var img_div = new Element("div", { className: "imageup" });
  img_div.appendChild(document.createTextNode("--"));
  $('imagelist').insertBefore(img_div, $("dropzone"));

  var upload =
    {
      file: file,
      div: img_div
    };

  if (active_uploads < 3) {
    _start_img_upload(upload);
  }
  else {
    queued_uploads.push(upload);
  }
}

function _start_img_upload(upload) {
  ++active_uploads;
  api.add_image_file({
    image: upload.file,
    name: "",
    id: last_article.id,
    onSuccess: function(upload, img) {
      upload.div.innerHTML = "";
      _fill_one_image(upload.div, img);
//       var img_img = new Element
// 	(
// 	"img",
// 	{
// 	  id: "img" + img.id,
// 	  src: api.thumb_link(img, "sadmingall")
// 	});
//       upload.div.appendChild(img_img);
//       upload.div.id = "imgdiv" + img.id;
//       upload.div.className = "";

    }.bind(this, upload),
    onFailure: function(upload) {
      upload.div.parentNode.removeChild(upload.div);
      alert("upload error");
    }.bind(this, upload),
    //onStart: _progress_start,
    onComplete: function() {
      --active_uploads;
      if (queued_uploads.length) {
	var upload = queued_uploads.shift();
	_start_img_upload(upload);
      }
    },
    onProgress: function(upload, prog) {
      if (prog.total) {
	var per_thou =
	  Math.round(prog.done / prog.total * 1000);
	upload.div.innerHTML = "" + Math.floor(per_thou / 10) + "."
	  + per_thou % 10 + "%";
      }
    }.bind(this, upload)
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
  var alt = $("imagealt").value;
  api.add_image_file({
    image: file,
    name: name,
    alt: alt,
    id: last_article.id,
    clone: true,
    onSuccess: function (im) {
      var div = new Element("div");
      _fill_one_image(div, im);
      $("imagelist").appendChild(div);
      _make_images_orderable();
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

var current_window;
function _open_window(ele, title) {
  var closer = $("windowclose");
  closer.parentNode.removeChild(closer);
  if (title) {
    ele.firstDescendant().innerHTML = "";
    ele.firstDescendant().appendChild(document.createTextNode(title));
  }
  ele.firstDescendant().appendChild(closer);
  current_window=ele;
  ele.style.display="block";
}

function _close_window() {
  current_window.style.display="none";
  return false;
}

function _start_edit_image(im) {
  var form = $("image_edit_form");
  form.reset();
  form.alt.value = im.alt;
  form.name.value = im.name;
  form.url.value = im.url;
  form.onsubmit = _do_save_image.bind(this, im);

  _open_window($("image_edit"));

  return false;
}

function _do_save_image(im) {
  var form = $("image_edit_form");

  api.save_image_file
  ({
     id: im.articleId,
     image_id: im.id,
     alt: form.alt.value,
     url: form.url.value,
     image: form.file,
     name: form.name.value,
     // storage: form.storage.value,
     clone: true,

     onSuccess: function(im) {
       var div = $("imgdiv"+im.id);
       div.innerHTML = "";
       _fill_one_image(div, im);
       _close_window();
     },
     onFailure: function(err) {
       alert(err.error_code);
     }
  });

  return false;
}

function _start_delete_image(im) {
  if (window.confirm("Are you sure you want to delete this image?")) {
    api.remove_image_file
    ({
       image: im,
       onSuccess: function(image_id) {
	 var div = $("imgdiv"+im.id);
	 div.parentNode.removeChild(div);
       }.bind(this, im.id),
       onFailure: function(err) {
         alert(err.error_code);
       }
     });
  }
}