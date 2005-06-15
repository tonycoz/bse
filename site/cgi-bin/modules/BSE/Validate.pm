package BSE::Validate;
use strict;
use base 'DevHelp::Validate';
use DevHelp::Validate qw(dh_validate dh_validate_hash dh_configure_fields);
use vars qw(@EXPORT @EXPORT_OK);
@EXPORT = ();
@EXPORT_OK = qw(bse_validate bse_validate_hash bse_configure_fields);

sub bse_validate {
  return dh_validate(@_);
}

sub bse_validate_hash {
  return dh_validate_hash(@_);
}

sub bse_configure_fields {
  return dh_configure_fields(@_);
}

1;

=head1 NAME

BSE::Validate - intended for future BSE specific expansion of
DevHelp::Validate.

=head1 SYNOPSIS

  $req->validate(fields=>$fields, rules=>$rules, errors=>\%errors);
  $req->validate_hash(fields=>$fields, rules=>$rules, errors=>\%errors, 
                      data=>\%hash)

=head1 DESCRIPTION



=cut
