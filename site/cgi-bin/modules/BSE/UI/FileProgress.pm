package BSE::UI::FileProgress;

sub dispatch {
  my ($class, $req) = @_;

  if ($req->cgi->param("dump")) {
return
+{
    type => "text/plain",
    content => join("\n", keys %INC)."\n",
};
  }

  my $cgi = $req->cgi;
  my $key = $cgi->param("_upload");
  my $result;
  if ($key) {
    my $cached = $req->cache_get("upload-$key");
    if ($cached) {
      $result =
	{
	 success => 1,
	 progress => $cached,
	};
    }
    else {
      $result =
	{
	 success => 1,
	 progress => [],
	};
    }
  }
  else {
    $result =
      {
       success => 0,
       message => "missing _upload parameter",
      };
  }

  return $req->json_content($result);
}

1;
