package BSE::Modules;
use strict;

# automatically generated

our $hash = "26303b0864eb8a4efa69f3a06972c63c";

our %versions =
  (
  "AdminUtil" => "1.000",
  "Apache::Session::DBIreal" => "1.000",
  "Apache::Session::Store::DBIreal" => "1.000",
  "Article" => "1.002",
  "Articles" => "1.000",
  "BSE::API" => "1.000",
  "BSE::Admin::StepParents" => "1.000",
  "BSE::AdminLogon" => "1.001",
  "BSE::AdminMenu" => "1.000",
  "BSE::AdminSiteUsers" => "1.000",
  "BSE::AdminUsers" => "1.000",
  "BSE::Arrows" => "1.000",
  "BSE::CGI" => "1.000",
  "BSE::Cache" => "1.000",
  "BSE::Cache::CHI" => "1.001",
  "BSE::Cache::Cache" => "1.000",
  "BSE::Cache::Memcached" => "1.000",
  "BSE::Cfg" => "1.002",
  "BSE::CfgInfo" => "1.000",
  "BSE::ChangePW" => "1.000",
  "BSE::ComposeMail" => "1.001",
  "BSE::Countries" => "1.000",
  "BSE::Custom" => "1.000",
  "BSE::CustomBase" => "1.000",
  "BSE::DB" => "1.000",
  "BSE::DB::Mysql" => "1.000",
  "BSE::Dynamic::Article" => "1.000",
  "BSE::Dynamic::Catalog" => "1.000",
  "BSE::Dynamic::Product" => "1.000",
  "BSE::Dynamic::Seminar" => "1.000",
  "BSE::Edit::Article" => "1.003",
  "BSE::Edit::Base" => "1.000",
  "BSE::Edit::Catalog" => "1.001",
  "BSE::Edit::Product" => "1.001",
  "BSE::Edit::Seminar" => "1.000",
  "BSE::Edit::Site" => "1.000",
  "BSE::EmailBlackEntry" => "1.000",
  "BSE::EmailBlacklist" => "1.000",
  "BSE::EmailRequest" => "1.000",
  "BSE::EmailRequests" => "1.000",
  "BSE::FileHandler::Base" => "1.000",
  "BSE::FileHandler::Default" => "1.000",
  "BSE::FileHandler::FLV" => "1.000",
  "BSE::FileMetaMeta" => "1.000",
  "BSE::Formatter" => "1.001",
  "BSE::Formatter::Article" => "1.000",
  "BSE::Formatter::Subscription" => "1.000",
  "BSE::Generate::Seminar" => "1.000",
  "BSE::ImageHandler::Base" => "1.000",
  "BSE::ImageHandler::Flash" => "1.000",
  "BSE::ImageHandler::Img" => "1.000",
  "BSE::ImportSourceBase" => "1.000",
  "BSE::ImportSourceXLS" => "1.000",
  "BSE::ImportTargetArticle" => "1.000",
  "BSE::ImportTargetBase" => "1.000",
  "BSE::ImportTargetProduct" => "1.000",
  "BSE::Importer" => "1.000",
  "BSE::Index::BSE" => "1.000",
  "BSE::Index::Base" => "1.000",
  "BSE::Jobs::AuditClean" => "1.000",
  "BSE::Mail" => "1.000",
  "BSE::Mail::SMTP" => "1.000",
  "BSE::Mail::Sendmail" => "1.000",
  "BSE::Message" => "1.002",
  "BSE::MessageScanner" => "1.000",
  "BSE::NLFilter::SQL" => "1.000",
  "BSE::NotifyFiles" => "1.000",
  "BSE::Password::Crypt" => "1.000",
  "BSE::Password::CryptMD5" => "1.000",
  "BSE::Password::CryptSHA256" => "1.000",
  "BSE::Password::Plain" => "1.000",
  "BSE::Passwords" => "1.000",
  "BSE::PayPal" => "1.001",
  "BSE::Permissions" => "1.000",
  "BSE::ProductImportXLS" => "1.000",
  "BSE::Report" => "1.000",
  "BSE::Request" => "1.000",
  "BSE::Request::Base" => "1.001",
  "BSE::Request::Test" => "1.000",
  "BSE::Search::BSE" => "1.000",
  "BSE::Search::Base" => "1.000",
  "BSE::Session" => "1.000",
  "BSE::Shipping" => "1.000",
  "BSE::Shop::Util" => "1.003",
  "BSE::Sort" => "1.000",
  "BSE::Storage::AmazonS3" => "1.000",
  "BSE::Storage::Base" => "1.000",
  "BSE::Storage::FTP" => "1.000",
  "BSE::Storage::LocalBase" => "1.000",
  "BSE::Storage::LocalFiles" => "1.000",
  "BSE::Storage::LocalImages" => "1.000",
  "BSE::Storage::LocalThumbs" => "1.000",
  "BSE::StorageMgr::Base" => "1.000",
  "BSE::StorageMgr::Files" => "1.000",
  "BSE::StorageMgr::Images" => "1.000",
  "BSE::StorageMgr::Thumbs" => "1.000",
  "BSE::SubscribedUser" => "1.000",
  "BSE::SubscribedUsers" => "1.000",
  "BSE::SubscriptionType" => "1.000",
  "BSE::SubscriptionTypes" => "1.000",
  "BSE::TB::AdminBase" => "1.000",
  "BSE::TB::AdminBases" => "1.000",
  "BSE::TB::AdminGroup" => "1.000",
  "BSE::TB::AdminGroups" => "1.000",
  "BSE::TB::AdminMembership" => "1.000",
  "BSE::TB::AdminMemberships" => "1.000",
  "BSE::TB::AdminPerm" => "1.000",
  "BSE::TB::AdminPerms" => "1.000",
  "BSE::TB::AdminUIState" => "1.000",
  "BSE::TB::AdminUIStates" => "1.000",
  "BSE::TB::AdminUser" => "1.001",
  "BSE::TB::AdminUsers" => "1.000",
  "BSE::TB::ArticleFile" => "1.002",
  "BSE::TB::ArticleFileMeta" => "1.000",
  "BSE::TB::ArticleFileMetas" => "1.000",
  "BSE::TB::ArticleFiles" => "1.000",
  "BSE::TB::AuditEntry" => "1.002",
  "BSE::TB::AuditLog" => "1.001",
  "BSE::TB::BackgroundTask" => "1.000",
  "BSE::TB::BackgroundTasks" => "1.000",
  "BSE::TB::FileAccessLog" => "1.000",
  "BSE::TB::FileAccessLogEntry" => "1.000",
  "BSE::TB::Image" => "1.001",
  "BSE::TB::Images" => "1.000",
  "BSE::TB::Location" => "1.001",
  "BSE::TB::Locations" => "1.000",
  "BSE::TB::Order" => "1.001",
  "BSE::TB::OrderItem" => "1.000",
  "BSE::TB::OrderItemOption" => "1.000",
  "BSE::TB::OrderItemOptions" => "1.000",
  "BSE::TB::OrderItems" => "1.000",
  "BSE::TB::Orders" => "1.000",
  "BSE::TB::OwnedFile" => "1.000",
  "BSE::TB::OwnedFiles" => "1.000",
  "BSE::TB::ProductOption" => "1.000",
  "BSE::TB::ProductOptionValue" => "1.000",
  "BSE::TB::ProductOptionValues" => "1.000",
  "BSE::TB::ProductOptions" => "1.000",
  "BSE::TB::Seminar" => "1.000",
  "BSE::TB::SeminarBooking" => "1.000",
  "BSE::TB::SeminarBookings" => "1.000",
  "BSE::TB::SeminarSession" => "1.000",
  "BSE::TB::SeminarSessions" => "1.000",
  "BSE::TB::Seminars" => "1.000",
  "BSE::TB::Site" => "1.000",
  "BSE::TB::SiteCommon" => "1.000",
  "BSE::TB::SiteUserGroup" => "1.000",
  "BSE::TB::SiteUserGroups" => "1.000",
  "BSE::TB::Subscription" => "1.000",
  "BSE::TB::Subscription::Calc" => "1.000",
  "BSE::TB::Subscriptions" => "1.000",
  "BSE::TagFormats" => "1.000",
  "BSE::Template" => "1.000",
  "BSE::Thumb::Imager" => "1.000",
  "BSE::Thumb::Imager::Colourize" => "1.000",
  "BSE::Thumb::Imager::RandomCrop" => "1.000",
  "BSE::ThumbLow" => "1.000",
  "BSE::UI::API" => "1.000",
  "BSE::UI::AdminAudit" => "1.000",
  "BSE::UI::AdminDispatch" => "1.000",
  "BSE::UI::AdminMessages" => "1.000",
  "BSE::UI::AdminModules" => "1.001",
  "BSE::UI::AdminNewsletter" => "1.000",
  "BSE::UI::AdminPregen" => "1.000",
  "BSE::UI::AdminReport" => "1.000",
  "BSE::UI::AdminSeminar" => "1.000",
  "BSE::UI::AdminSendEmail" => "1.000",
  "BSE::UI::AdminShop" => "1.001",
  "BSE::UI::Affiliate" => "1.000",
  "BSE::UI::Background" => "1.000",
  "BSE::UI::Dispatch" => "1.000",
  "BSE::UI::FileProgress" => "1.000",
  "BSE::UI::Formmail" => "1.001",
  "BSE::UI::Image" => "1.000",
  "BSE::UI::NAdmin" => "1.000",
  "BSE::UI::NUser" => "1.000",
  "BSE::UI::Page" => "1.001",
  "BSE::UI::Redirect" => "1.000",
  "BSE::UI::Search" => "1.000",
  "BSE::UI::Shop" => "1.007",
  "BSE::UI::SiteUserUpdate" => "1.000",
  "BSE::UI::SiteuserCommon" => "1.000",
  "BSE::UI::SubAdmin" => "1.000",
  "BSE::UI::Tellafriend" => "1.000",
  "BSE::UI::Thumb" => "1.000",
  "BSE::UI::User" => "1.000",
  "BSE::UI::UserCommon" => "1.000",
  "BSE::UserReg" => "1.005",
  "BSE::Util::ContentType" => "1.000",
  "BSE::Util::DynSort" => "1.000",
  "BSE::Util::DynamicTags" => "1.003",
  "BSE::Util::HTML" => "1.000",
  "BSE::Util::Iterate" => "1.001",
  "BSE::Util::Prereq" => "1.001",
  "BSE::Util::SQL" => "1.000",
  "BSE::Util::Secure" => "1.000",
  "BSE::Util::Tags" => "1.003",
  "BSE::Util::Thumb" => "1.000",
  "BSE::Util::Valid" => "1.000",
  "BSE::Validate" => "1.000",
  "BSE::Version" => "0.19",
  "BSE::WebUtil" => "1.000",
  "Constants" => "1.000",
  "Courier" => "1.000",
  "Courier::AustraliaPost" => "1.000",
  "Courier::AustraliaPost::Air" => "1.000",
  "Courier::AustraliaPost::Express" => "1.000",
  "Courier::AustraliaPost::Sea" => "1.000",
  "Courier::AustraliaPost::Standard" => "1.000",
  "Courier::Fastway" => "1.000",
  "Courier::Fastway::Road" => "1.000",
  "Courier::Fastway::Satchel" => "1.000",
  "Courier::Null" => "1.000",
  "DevHelp::Cfg" => "1.000",
  "DevHelp::Date" => "1.000",
  "DevHelp::DynSort" => "1.000",
  "DevHelp::FileUpload" => "1.000",
  "DevHelp::Formatter" => "1.000",
  "DevHelp::HTML" => "1.000",
  "DevHelp::LoaderData" => "1.000",
  "DevHelp::Payments::Inpho" => "1.000",
  "DevHelp::Payments::SecurePayXML" => "1.000",
  "DevHelp::Payments::Test" => "1.000",
  "DevHelp::Report" => "1.000",
  "DevHelp::Tags" => "1.000",
  "DevHelp::Tags::Iterate" => "1.003",
  "DevHelp::Validate" => "1.000",
  "Generate" => "1.002",
  "Generate::Article" => "1.000",
  "Generate::Catalog" => "1.000",
  "Generate::Product" => "1.000",
  "Generate::Subscription" => "1.000",
  "OtherParent" => "1.000",
  "OtherParents" => "1.000",
  "Product" => "1.000",
  "Products" => "1.000",
  "SiteUser" => "1.002",
  "SiteUsers" => "1.000",
  "Squirrel::GPG" => "1.000",
  "Squirrel::PGP5" => "1.000",
  "Squirrel::PGP6" => "1.000",
  "Squirrel::Row" => "1.001",
  "Squirrel::Table" => "1.002",
  "Squirrel::Template" => "1.001",
  "Util" => "1.000",
  );

our %file_versions =
  (
  "db/bse_background_tasks.data" => "1.000",
  "db/bse_msg_base.data" => "1.000",
  "db/bse_msg_defaults.data" => "1.000",
  "db/sql_statements.data" => "1.000",
  );

1;
