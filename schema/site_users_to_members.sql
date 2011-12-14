delimiter ;;

drop procedure if exists bse_update_siteusers;;
create procedure bse_update_siteusers()
begin
  declare sucount integer;
  declare cur cursor for
    select count(*) from bse_siteusers;
  open cur;
  fetch cur into sucount;
  if sucount <> 0 then
    call error_bse_siteusers_must_be_empty;
  end if;
  insert into bse_siteusers
select
  id,
  uuid() as "idUUID",
  userId,
  password,
  password_type,
  email,
  whenRegistered,
  lastLogon,
  title,
  name1,
  name2,
  address as "street",
  delivStreet2 as "street2",
  city as "billSuburb",
  state as "billState",
  postcode,
  country,
  telephone,
  facsimile,
  delivMobile as "mobile",
  organization,
  confirmed,
  confirmSecret,
  waitingForConfirmation,
  textOnlyMail,
  previousLogon,
  '' as delivTitle,
  '' as delivEmail,
  '' as delivFirstName,
  '' as delivLastName,
  '' as delivStreet,
  '' as delivStreet2,
  '' as delivSuburb,
  '' as delivState,
  '' as delivPostCode,
  '' as delivCountry,
  '' as delivTelephone,
  '' as delivFacsimile,
  '' as delivMobile,
  '' as delivOrganization,
  instructions,
  adminNotes,
  disabled,
  flags,
  affiliate_name,
  lost_today,
  lost_date,
  lost_id,
  customText1,
  customText2,
  customText3,
  customStr1,
  customStr2,
  customStr3,
  customInt1,
  customInt2,
  null as customWhen1
from site_users;
end;;

delimiter ;

call bse_update_siteusers;

drop procedure bse_update_siteusers;
