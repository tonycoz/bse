delimiter ;;
drop procedure if exists bse_ip_lockout;
create procedure bse_ip_lockout(
  pip_address varchar(20),
  ptype char,
  plockout_end datetime)
begin
  insert bse_ip_lockouts(ip_address, type, expires)
    values(pip_address, ptype, plockout_end)
    on duplicate key update expires = plockout_end;
end;;
