package Courier::AustraliaPost;

use strict;
use Courier;
use LWP::UserAgent;

our @ISA = qw(Courier);

my %countries;
while (<DATA>) {
    chomp;
    next if /^#/ || /^\s*$/;
    my ($code, $country) = split /\s+/, $_, 2;
    $countries{$country} = $code;
}

my $ua;
my $url = "http://drc.edeliver.com.au/ratecalc.asp";
my @fields =
    qw(Pickup_Postcode Destination_Postcode Country
       Weight Service_Type Length Width Height Quantity);

sub new {
    my ($class, %args) = @_;

    $ua = LWP::UserAgent->new;
    return $class->SUPER::new(%args);
}

sub can_deliver {
    return 1;
}

sub calculate_shipping {
    my ($self) = @_;

    my %data = ();

    $data{Service_Type} = $self->{type};
    $data{Pickup_Postcode} =
        $self->{config}->entry("shipping", "sourcepostcode");
    $data{Destination_Postcode} = $self->{order}->{delivPostCode};
    $data{Country} = $countries{lc $self->{order}->{delivCountry}};
    $data{Quantity} = 1;
    $data{Weight} = $self->{weight};
    $data{Length} = $self->{length};
    $data{Height} = $self->{height};
    $data{Width} = $self->{width};

    my $u = URI->new($url);
    my $r = $ua->post($u, \%data);

    if ($r->is_success) {
        my @lines = split /\r?\n/, $r->content;
        foreach (@lines) {
            if (/^charge=(.*)$/) {
                $self->{cost} = $1;
            }
            elsif (/^days=(.*)$/) {
                $self->{days} = $1;
            }
            elsif (/^err_msg=(.*)$/) {
                $self->{error} = $1;
            }
        }
    }
    else {
        warn $u->as_string(). ": ". $r->status_line, "\n";
        $self->{error} = "Server error";
    }
}

1;

__DATA__
# <pre>
# @(#)iso3166.tab	8.6
# This file is in the public domain, so clarified as of
# 2009-05-17 by Arthur David Olson.
# ISO 3166 alpha-2 country codes
#
# From Paul Eggert (2006-09-27):
#
# This file contains a table with the following columns:
# 1.  ISO 3166-1 alpha-2 country code, current as of
#     ISO 3166-1 Newsletter VI-1 (2007-09-21).  See:
#     <a href="http://www.iso.org/iso/en/prods-services/iso3166ma/index.html">
#     ISO 3166 Maintenance agency (ISO 3166/MA)
#     </a>.
# 2.  The usual English name for the country,
#     chosen so that alphabetic sorting of subsets produces helpful lists.
#     This is not the same as the English name in the ISO 3166 tables.
#
# Columns are separated by a single tab.
# The table is sorted by country code.
#
# Lines beginning with `#' are comments.
#
#country-
#code	country name
AD	Andorra
AE	United Arab Emirates
AF	Afghanistan
AG	Antigua & Barbuda
AI	Anguilla
AL	Albania
AM	Armenia
AN	Netherlands Antilles
AO	Angola
AQ	Antarctica
AR	Argentina
AS	Samoa (American)
AT	Austria
AU	Australia
AW	Aruba
AX	Aaland Islands
AZ	Azerbaijan
BA	Bosnia & Herzegovina
BB	Barbados
BD	Bangladesh
BE	Belgium
BF	Burkina Faso
BG	Bulgaria
BH	Bahrain
BI	Burundi
BJ	Benin
BL	St Barthelemy
BM	Bermuda
BN	Brunei
BO	Bolivia
BR	Brazil
BS	Bahamas
BT	Bhutan
BV	Bouvet Island
BW	Botswana
BY	Belarus
BZ	Belize
CA	Canada
CC	Cocos (Keeling) Islands
CD	Congo (Dem. Rep.)
CF	Central African Rep.
CG	Congo (Rep.)
CH	Switzerland
CI	Cote d'Ivoire
CK	Cook Islands
CL	Chile
CM	Cameroon
CN	China
CO	Colombia
CR	Costa Rica
CU	Cuba
CV	Cape Verde
CX	Christmas Island
CY	Cyprus
CZ	Czech Republic
DE	Germany
DJ	Djibouti
DK	Denmark
DM	Dominica
DO	Dominican Republic
DZ	Algeria
EC	Ecuador
EE	Estonia
EG	Egypt
EH	Western Sahara
ER	Eritrea
ES	Spain
ET	Ethiopia
FI	Finland
FJ	Fiji
FK	Falkland Islands
FM	Micronesia
FO	Faroe Islands
FR	France
GA	Gabon
GB	Britain (UK)
GD	Grenada
GE	Georgia
GF	French Guiana
GG	Guernsey
GH	Ghana
GI	Gibraltar
GL	Greenland
GM	Gambia
GN	Guinea
GP	Guadeloupe
GQ	Equatorial Guinea
GR	Greece
GS	South Georgia & the South Sandwich Islands
GT	Guatemala
GU	Guam
GW	Guinea-Bissau
GY	Guyana
HK	Hong Kong
HM	Heard Island & McDonald Islands
HN	Honduras
HR	Croatia
HT	Haiti
HU	Hungary
ID	Indonesia
IE	Ireland
IL	Israel
IM	Isle of Man
IN	India
IO	British Indian Ocean Territory
IQ	Iraq
IR	Iran
IS	Iceland
IT	Italy
JE	Jersey
JM	Jamaica
JO	Jordan
JP	Japan
KE	Kenya
KG	Kyrgyzstan
KH	Cambodia
KI	Kiribati
KM	Comoros
KN	St Kitts & Nevis
KP	Korea (North)
KR	Korea (South)
KW	Kuwait
KY	Cayman Islands
KZ	Kazakhstan
LA	Laos
LB	Lebanon
LC	St Lucia
LI	Liechtenstein
LK	Sri Lanka
LR	Liberia
LS	Lesotho
LT	Lithuania
LU	Luxembourg
LV	Latvia
LY	Libya
MA	Morocco
MC	Monaco
MD	Moldova
ME	Montenegro
MF	St Martin (French part)
MG	Madagascar
MH	Marshall Islands
MK	Macedonia
ML	Mali
MM	Myanmar (Burma)
MN	Mongolia
MO	Macau
MP	Northern Mariana Islands
MQ	Martinique
MR	Mauritania
MS	Montserrat
MT	Malta
MU	Mauritius
MV	Maldives
MW	Malawi
MX	Mexico
MY	Malaysia
MZ	Mozambique
NA	Namibia
NC	New Caledonia
NE	Niger
NF	Norfolk Island
NG	Nigeria
NI	Nicaragua
NL	Netherlands
NO	Norway
NP	Nepal
NR	Nauru
NU	Niue
NZ	New Zealand
OM	Oman
PA	Panama
PE	Peru
PF	French Polynesia
PG	Papua New Guinea
PH	Philippines
PK	Pakistan
PL	Poland
PM	St Pierre & Miquelon
PN	Pitcairn
PR	Puerto Rico
PS	Palestine
PT	Portugal
PW	Palau
PY	Paraguay
QA	Qatar
RE	Reunion
RO	Romania
RS	Serbia
RU	Russia
RW	Rwanda
SA	Saudi Arabia
SB	Solomon Islands
SC	Seychelles
SD	Sudan
SE	Sweden
SG	Singapore
SH	St Helena
SI	Slovenia
SJ	Svalbard & Jan Mayen
SK	Slovakia
SL	Sierra Leone
SM	San Marino
SN	Senegal
SO	Somalia
SR	Suriname
ST	Sao Tome & Principe
SV	El Salvador
SY	Syria
SZ	Swaziland
TC	Turks & Caicos Is
TD	Chad
TF	French Southern & Antarctic Lands
TG	Togo
TH	Thailand
TJ	Tajikistan
TK	Tokelau
TL	East Timor
TM	Turkmenistan
TN	Tunisia
TO	Tonga
TR	Turkey
TT	Trinidad & Tobago
TV	Tuvalu
TW	Taiwan
TZ	Tanzania
UA	Ukraine
UG	Uganda
UM	US minor outlying islands
US	United States
UY	Uruguay
UZ	Uzbekistan
VA	Vatican City
VC	St Vincent
VE	Venezuela
VG	Virgin Islands (UK)
VI	Virgin Islands (US)
VN	Vietnam
VU	Vanuatu
WF	Wallis & Futuna
WS	Samoa (western)
YE	Yemen
YT	Mayotte
ZA	South Africa
ZM	Zambia
ZW	Zimbabwe
