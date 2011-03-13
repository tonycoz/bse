var BSEValidator = Class.create({
  initialize: function(options) {
    this.options = Object.extend(
      Object.extend({}, this.defaults()));
  },
  _validator: function(rule) {
    return new BSEValidator.Rules[rule];
  },
  _format: function(message, field) {
    return message.replace(/\$n/, field.description());
  },
  validate_one: function(field, fields, errors) {
    if (field.required() && !field.has_value()) {
      errors.set(field.name(), this._format(this.options.required_error, field));
      return false;
    }
    var rules = field.rules();
    var value = field.value();
    if (typeof(rules) == "string") {
      rules = rules.split(/;/);
    }
    for (var i = 0; i < rules.length; ++i) {
      var rule = rules[i];
      if (rule == "")
	continue;
      var rest = "";
      var m = /^([0-9a-z_]+):(.*)$/.exec(rule);
      if (m) {
	rule = m[1];
	rest = m[2];
      }
      var cls = this._validator(rule);
      try {
	var result = cls.test(value, this.options, rest, fields);
	try {
	  field.set_object(result);
	}
	catch(e) {
	  // ignore
	}
      }
      catch (e) {
	errors.set(field.name(), e.message.replace(/\$n/, field.description()));
	return false;
      }
    }
    return true;
  },
  validate: function(fields, errors) {
    fields.each(function(fields, errors, entry) {
      this.validate_one(entry.value, fields, errors);
    }.bind(this, fields, errors));

    return errors.values().length == 0;
  },
  defaults: function() {
    return BSEValidator.defaults;
  }
});

BSEValidator.defaults = {
  required_error: "$n is required"
};

BSEValidator.Rules = {};

BSEValidator.Rules.Base = Class.create({
});

BSEValidator.Rules["date"] = Class.create(BSEValidator.Rules.Base, {
  _days: [ 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ],
  _days_in_month: function(year, month) {
    if (month == 2) {
      if (year % 4 == 0 && year % 100 != 0 || year % 400 == 0)
	return 29;
      else
	return 28;
    }
    else {
      return this._days[month-1];
    }
  },
  _parse_limit: function(limit) {
    var m = /^([0-9]+)[^0-9]([0-9]+)[^0-9]([0-9]+)$/.exec(limit);
    if (m) {
      // yyyy-mm-dd
      return new Date(parseInt(m[1]), parseInt(m[2])-1, parseInt(m[3]));
    }

    var base = new Date();
    m = /^([+-][0-9]+)y/.match(limit);
    if (m) {
      base.setFullYear(base.getFullYear() + parseInt(m[1]));
      return base;
    }

    m = /^([+-][0-9]+)y/.match(limit);
    if (m) {
      // adjust by ms/day
      base.setMilliseconds(base.valueOf() + parseInt(m[1]) & 86400000);
      return base;
    }

    throw new Error("Cannot parse date limit " + limit);
  },
  default_options: function() {
    return BSEValidator.Rules["date"].defaults;
  },
  min_date: function() {
    return null;
  },
  max_date: function() {
    return null;
  },
  test: function(value, options, rest) {
    options = Object.extend(Object.extend({}, this.default_options()), options);
    var m = options.date_re.exec(value);
    if (!m)
      throw new Error(options.date_format_error);

    var day, month, year;
    var format = options.date_order.split("");
    for (var i = 0; i < format.length; ++i) {
      switch (format[i]) {
      case "d":
	day = parseInt(m[1+i]);
	break;
      case "m":
	month = parseInt(m[1+i]);
	break;
      case "y":
	year = parseInt(m[1+i]);
	break;
      }
    }
    if (month < 1 || month > 12)
      throw new Error(options.date_month_range_error);
    if (day < 1 || day > this._days_in_month(year, month))
      throw new Error(options.date_day_range_error);

    var min_date = this.min_date();
    if (min_date != null) {
      var min = this._parse_limit(min_date);
      if (min.getTime() > result.getTime())
	throw new Error(options.date_too_low_error);
    }
    var max_date = this.max_date();
    if (options.max_date != null) {
      var max = this._parse_limit(max_date);
      if (max.getTime() < result.getTime())
	throw new Error(options.date_too_high_error);
    }
    
    var result = new Date(year, month-1, day);

    return result;
  }
});

BSEValidator.Rules["date"].defaults = {
  date_re: /^\s*([0-9]+)[\/-]([0-9]+)[\/-]([0-9]+)\s*/,
  date_order: "dmy",
  date_format_error: "$n must be dd/mm/yyyy",
  date_month_range_error: "Month out of range for $n",
  date_day_range_error: "Day out of range for $n",
  date_too_high_error: "$n too late",
  date_too_low_error: "$n too early"
};

BSEValidator.Rules["future"] = Class.create(BSEValidator.Rules["date" ], {
  min_date: function() {
    var date = new Date();
    date.setHours(0, 0, 0, 0);
    return date;
  },
  default_options: function() {
    return BSEValidator.Rules["future"].defaults;
  }
});

BSEValidator.Rules["future"].defaults =
  Object.extend({
    date_too_low_error: "$n must be be in the future"
  }, BSEValidator.Rules["date"].defaults);

BSEValidator.Rules["confirm"] = Class.create(BSEValidator.Rules.Base, {
  test: function(value, options, rest, fields) {
    options = Object.extend(Object.extend({}, BSEValidator.Rules["confirm"].defaults), options);
    var other = fields.get(rest).value();

    if (value != other) {
      var msg = options.confirm_error;
      msg = msg.replace(/\$o/, fields.get(rest).description());
      throw Error(msg);
    }

    return value;
  }
});

BSEValidator.Rules["confirm"].defaults = {
  confirm_error: "$n must be the same as $o"
};

