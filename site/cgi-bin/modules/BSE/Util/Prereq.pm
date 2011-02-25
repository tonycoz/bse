package BSE::Util::Prereq;
use strict;

our $VERSION = "1.002";

# pre-requisites for various modules

our %prereqs =
  (
   "BSE::Cache::Memcached" => [ "Cache::Memcached::Fast" ],
   "BSE::ImportSourceXLS" => [ "Spreadsheet::ParseExcel" ],
   "BSE::ProductImportXLS" => [ "Spreadsheet::ParseExcel" ],
   "BSE::Storage::AmazonS3" => [ "Net::Amazon::S3" ],
   "BSE::Util::ValidateHTML::Tidy" => [ "HTML::Tidy" ],
   "BSE::Util::ValidateHTML::W3C" => [ "WebService::Validator::HTML::W3C", "XML::XPath" ],
   "Courier::Fastway" => [ "XML::Parser" ],
   "Courier::Fastway::Road" => [ "XML::Parser" ],
   "Courier::Fastway::Satchel" => [ "XML::Parser" ],
   "DevHelp::Payments::SecurePayXML" => [ "XML::Simple" ],
  );
