var bse_image_popup;
function bse_popup_image (article_id, image_id, width, height, tag_id, image_url) {
  var url = "/cgi-bin/image.pl?id=" + article_id + "&imid=" + image_id
	+ '&comment=jspopup';
  var work_width = width;
  var work_height = height;
  var features = 'width=' + work_width + ',height=' + work_height
    + ',resizable=yes';

  // lose the old one if it exists
  if (bse_image_popup != null && !bse_image_popup.closed) {
    bse_image_popup.close();
  }
  var left = window.screenX + (window.outerWidth - work_width) / 2;
  var top = window.screenY + (window.outerHeight - work_height) / 2;
  features = features + ",top=" + top + ",left=" + left;

  bse_image_popup = window.open(url, 'bse_image', features, 0);

  return 0;
}

var bse_video_stage;
var bse_video_frame;
var bse_video_running = 0;

function bse_show_video (fileid, width, height, src) {
  if (bse_video_running) {
    bse_close_video();
    return false;
  }
  // check for our staging area
  if (!bse_video_stage) {
    bse_video_stage = document.getElementById("bse_video_stage");
    bse_video_frame = document.getElementById("bse_video_frame");
    bse_video_close = document.getElementById("bse_video_close");
  }
  if (!bse_video_stage) {
    bse_video_stage = document.createElement("div");
    bse_video_stage.id = "bse_video_stage";
    bse_video_frame = document.createElement("div");
    bse_video_frame.id = "bse_video_frame";
    bse_video_close = document.createElement("a");
    bse_video_close.href="#";
    bse_video_close.onclick = bse_close_video;
    bse_video_close.id = "bse_video_close";
    bse_video_stage.appendChild(bse_video_frame);
    bse_video_stage.appendChild(bse_video_close);
    var img = document.createElement("img");
    img.src = "/images/videoclose.png";
    bse_video_close.appendChild(img);
    document.body.appendChild(bse_video_stage);
  }
  bse_video_frame.style.width = width + "px";
  bse_video_frame.style.height = height + "px";
  var margin = (-width / 2);
  bse_video_frame.style.marginLeft = margin + "px";
  bse_video_close.style.marginRight = (margin - 20) + "px";


  var so = new SWFObject("/swf/flvplayer.swf", "flvplayer", width, height, "8", "#000000");
  so.addParam('allowFullScreen',true);
  so.addVariable('aspect_ratio', width/height);
  //so.addVariable('placeholder','/cgi-bin/user.pl/file_metadata/'+fileid+'/ph_data');
  so.addVariable('video_path',src);
  so.addVariable('autoplay');
  so.write("bse_video_frame");

  bse_video_stage.style.display="block";

  bse_video_stage.onmousedown = "bse_close_video(); return false;";
  bse_video_running = 1;

  return false;
}

function bse_close_video() {
  bse_video_frame.innerHTML = '';
  bse_video_stage.style.display = "none";
  bse_video_running = 0;
  return false;
}