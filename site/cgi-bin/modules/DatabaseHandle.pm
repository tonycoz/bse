package DatabaseHandle;
require 5.005;

$DatabaseHandle::VERSION = '0.1';

use Constants 0.1 qw/$DBD $DB $UN $PW/;

use DBI;

my $self = undef;

sub single
{
	my $class = shift;
	warn "Incorrect number of parameters passed to DatabaseHandle::single\n" unless @_ == 0;

	unless ( defined $self )
	{
		my $dbh = DBI->connect( "DBI:$DBD:database=$DB", $UN, $PW)
		    or die "Cannot connect to database: $DBI::errstr";

		$self = bless { dbh => $dbh,
				Articles => $dbh->prepare('select * from article'),
				Images => $dbh->prepare('select * from image'),
				
				replaceArticle    => $dbh->prepare( 'replace article    values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'),
				replaceImage => $dbh->prepare('replace image values (?,?,?,?,?,?)'),

				addArticle    => $dbh->prepare( 'insert article values (null, ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'),
				addImage => $dbh->prepare('insert image values(null, ?, ?, ?, ?, ?)'),

				deleteArticle => $dbh->prepare( 'delete from article where id = ?'),
				deleteImage => $dbh->prepare('delete from image where id = ?'),

				getImageByArticleId => $dbh->prepare('select * from image where articleId = ?'),

				getArticleByPkey => $dbh->prepare('select * from article where id = ?'),

				getArticleByLevel => $dbh->prepare('select * from article where level = ?'),
				getArticleByParentid => $dbh->prepare('select * from article where parentid = ?'),
				dropIndex => $dbh->prepare('delete from searchindex'),
				insertIndex => $dbh->prepare('insert searchindex values(?, ?, ?, ?)'),
				searchIndex => $dbh->prepare('select * from searchindex where id = ?'),
				searchIndexWC => $dbh->prepare('select * from searchindex where id like ?'),

				Products=> $dbh->prepare('select article.*, product.* from article, product where id = articleId'),
				addProduct => $dbh->prepare('insert product values(?,?,?,?,?,?)'),
				getProductByPkey => $dbh->prepare('select article.*, product.* from article, product where id=? and articleId = id'),
				replaceProduct => $dbh->prepare('replace product values(?,?,?,?,?,?)'),

				Orders => $dbh->prepare('select * from orders'),
				getOrderByPkey => $dbh->prepare('select * from orders where id = ?'),
				getOrderItemByOrderId => $dbh->prepare('select * from order_item where orderId = ?'),
				addOrder => $dbh->prepare('insert orders values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'),
				addOrderItem => $dbh->prepare('insert order_item values(null,?,?,?,?,?,?)'),

			      }, $class;
	}
	$self;
}

# gotta love this
sub DESTROY
{
  # this is wierd - we only need to reset this on 5.6.x (for x == 0 so
  # far)
  # Works fine without the reset for 5.005_03
  if ($dbh) {
    $dbh->disconnect;
    undef $dbh;
  }
}

1;
