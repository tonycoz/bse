function preLoad()
{
	triFresh = new Image();
	triFresh.src = "triangle.gif";

	triActive = new Image();
	triActive.src = "invert.gif";
}

//--------------------------------------------------------------------
//
//  NeatDate class written by jason king (elephant@bigpond.com)
//
//  Javascript 1.0
//
//  Copyright © 1997 jason king. All rights reserved
//
//--------------------------------------------------------------------

// we make the NeatDate class the sort of date that Date should be but isn't

function NeatDate(datetimestring) {

if (datetimestring == null) {
	var realdate = new Date();
} else {
	var realdate = new Date(datetimestring);
}


var _numonth = realdate.getMonth() + 1;
var _hours = realdate.getHours();
var _minutes = realdate.getMinutes();
var _seconds = realdate.getSeconds();
var _milliseconds = realdate.getMilliseconds();

	this.day = this.days[realdate.getDay()];
	this.date = realdate.getDate() + suffix(realdate.getDate());
	this.month = this.months[realdate.getMonth()];
	this.suffix = suffix(realdate.getDate());
	this.hr12 = (_hours > 12 ? _hours - 12 : (_hours == 0 ? 12 : _hours))
		+ ":"
		+ (_minutes < 10 ? "0" + _minutes : _minutes)
		+ ":"
		+ (_seconds < 10 ? "0" + _seconds : _seconds)
		+ (_hours >= 12 ? "pm" : "am");
	this.hr24 = _hours
		+ ":"
		+ (_minutes < 10 ? "0" + _minutes : _minutes)
		+ ":"
		+ (_seconds < 10 ? "0" + _seconds : _seconds);
	this.year = realdate.getFullYear();
	this.numdate = (realdate.getDate() < 10 ? '0' : '') + realdate.getDate();
	this.numonth = (_numonth < 10 ? '0' : '') + _numonth;
	this.numyear = realdate.getYear();
	this.filedate = realdate.getYear() + this.numonth + this.numdate +
	                (_hours < 10 ? '0' : '') + _hours +
	                (_minutes < 10 ? '0' : '') + _minutes +
	                (_seconds < 10 ? '0' : '') + _seconds +
	                (_milliseconds < 10 ? '0' : '') + (_milliseconds < 100 ? '0' : '') + _milliseconds;
}

function suffix(day) {
	if (day > 10 && day < 20) return('th');
	if (day % 10 == 1) return('st');
	if (day % 10 == 2) return('nd');
	if (day % 10 == 3) return('rd');
	return('th');
}

//  defined as prototypes to save memory .. NB: Netscape3.0 would
//  require a NeatDate constructor before defining the prototype

NeatDate.prototype.days = new Array(
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday"
);

NeatDate.prototype.months = new Array(
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December"
);
