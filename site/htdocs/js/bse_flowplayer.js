document.write('<script type="text/javascript" src="/js/flowplayer-3.1.4.min.js"></script>');

var bse_flow_stage;
var bse_flow_frame;
var bse_flow_running = 0;

function bse_show_video_flow (fileid, width, height) {
  if (bse_flow_running) {
    bse_close_video_flow();
    return false;
  }
  // check for our staging area
  if (!bse_flow_stage) {
    bse_flow_stage = document.getElementById("bse_video_stage");
    bse_flow_frame = document.getElementById("bse_video_frame");
    bse_flow_close = document.getElementById("bse_video_close");
  }
  if (!bse_flow_stage) {
    bse_flow_stage = document.createElement("div");
    bse_flow_stage.id = "bse_video_stage";
    bse_flow_frame = document.createElement("div");
    bse_flow_frame.id = "bse_video_frame";
    bse_flow_close = document.createElement("a");
    bse_flow_close.href="#";
    bse_flow_close.onclick = bse_close_video_flow;
    bse_flow_close.id = "bse_video_close";
    bse_flow_stage.appendChild(bse_flow_frame);
    bse_flow_stage.appendChild(bse_flow_close);
    var img = document.createElement("img");
    img.src = "/images/videoclose.png";
    bse_flow_close.appendChild(img);
    document.body.appendChild(bse_flow_stage);
  }
  bse_flow_frame.style.width = width + "px";
  bse_flow_frame.style.height = height + "px";
  var margin = (-width / 2);
  bse_flow_frame.style.marginLeft = margin + "px";
  bse_flow_close.style.marginRight = (margin - 20) + "px";

  new Ajax.Request
    ("/cgi-bin/user.pl/file_cmetadata/"+fileid+"/flowplaylist",
    {
      method: "get",
      onSuccess: function(transport) {
	var playlist = eval(transport.responseText);
	flowplayer("bse_video_frame", "/swf/flowplayer-3.1.5.swf",
	     {
	       playlist: playlist
	     });

	bse_flow_stage.style.display="block";

	bse_flow_stage.onmousedown = "bse_close_video_flow(); return false;";
	bse_flow_running = 1;
      },
      onFailure: function() {
	alert("Could not retrieve video playlist");
      }
    });

  return false;
}

function bse_close_video_flow() {
  bse_flow_frame.innerHTML = '';
  bse_flow_stage.style.display = "none";
  bse_flow_running = 0;
  return false;
}
