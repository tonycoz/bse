build: flvplay.swf

flvplay.swf: lib/Player.hx resource.swf
	haxe -cp lib -swf flvplay.swf -swf-lib resource.swf -main Player -v

resource.swf: resource.xml resource/play.png
	swfmill -V -v simple resource.xml resource.swf

