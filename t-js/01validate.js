function validation_check(test, validator, checker) {
  if (test.exception) {
    var msg = ok_exception(function(validator, value) { 
      validator.test(value);
    }.bind(this, validator, test.value), "parse "+test.name, test.message);
    if (msg) {
      like(msg, test.message, "check message " + test.name);
    }
    else {
      ok(false, test.name + " no message");
    }
  }
  else {
    var a_parsed = ok_noexception(function(validator, value){
      return validator.test(value, {});
    }.bind(this, validator, test.value), "parse "+test.name);
    checker(a_parsed, test);
  }
}

document.observe("dom:loaded", function() {
  plan(55);
  diag("Date validation");
  var date_val = new BSEValidator.Rules["date"]();
  ok(date_val, "make date validator");
  var date_tests =
    [
      { 
	name: "birthday",
	value: "30/12/1967",
	exception: false,
	year: 1967,
	month: 12,
	day: 30
      },
      { 
	name: "birthday with spaces",
	value: " 30/12/1967 ",
	exception: false,
	year: 1967,
	month: 12,
	day: 30
      },
      {
	name: "low month",
	value: "30/0/1967",
	exception: true,
	message: /Month out of range/
      },
      {
	name: "low month in range",
	value: "30/1/1967",
	exception: false,
	year: 1967,
	month: 1,
	day: 30
      },
      {
	name: "high month",
	value: "30/13/1967",
	exception: true,
	message: /Month out of range/
      },
      {
	name: "high month in range",
	value: "30/12/1967",
	exception: false,
	year: 1967,
	month: 12,
	day: 30
      },
      {
	name: "high day normal",
	value: "32/12/1967",
	exception: true,
	message: /Day out of range/
      },
      {
	name: "high day normal in range",
	value: "31/12/1967",
	exception: false,
	year: 1967,
	month: 12,
	day: 31
      },
      {
	name: "high day non-leap",
	value: "29/2/1970",
	exception: true,
	message: /Day out of range/
      },
      {
	name: "high day non-leap in range",
	value: "28/2/1970",
	exception: false,
	year: 1970,
	month: 2,
	day: 28
      },
      {
	name: "high day leap",
	value: "30/2/1980",
	exception: true,
	message: /Day out of range/
      },
      {
	name: "high day leap in range",
	value: "29/2/1980",
	exception: false,
	year: 1980,
	month: 2,
	day: 29
      },
      {
	name: "low day",
	value: "0/1/1967",
	exception: true,
	message: /Day out of range/
      },
      {
	name: "low day in range",
	value: "1/1/1967",
	exception: false,
	year: 1967,
	month: 1,
	day: 1
      },
      {
	name: "bad format",
	value: "1/1/",
	exception: true,
	message: /must be dd\/mm\/yyyy$/
      }
    ];
  for (var i = 0; i < date_tests.length; ++i) {
    var test = date_tests[i];
    validation_check(test, date_val, function(a_date, test) {
      is(a_date.getFullYear(), test.year, test.name + " year");
      is(a_date.getMonth(), test.month-1, test.name + " month");
      is(a_date.getDate(), test.day, test.name + " day");
    });
  }

  var TestField = Class.create({
    initialize: function(options) {
      this.options = Object.extend({ required: false, rules: [] }, options);
    },
    value: function() {
      return this.options.value;
    },
    description: function() {
      return this.options.description
    },
    name: function() {
      return this.options.name;
    },
    rules: function() {
      return this.options.rules;
    },
    has_value: function() {
      return /\S/.test(this.value());
    },
    required: function() {
      return this.options.required;
    }
  });

  { // required
    var fields = new Hash({
      nr1: new TestField({
	name: "nr1",
	value: "",
	description: "NotRequired1"
      }),
      nr2: new TestField({
	name: "nr2",
	value: " ",
	description: "NotRequired2"
      }),
      r1: new TestField({
	name: "r1",
	value: "",
	required: true,
	description: "Required1"
      }),
      r2: new TestField({
	name: "r2",
	value: " ",
	required: true,
	description: "Required2"
      }),
      r3: new TestField({
	name: "r3",
	value: "x",
	required: true,
	description: "Required3"
      })
    });
    var val = new BSEValidator();
    var errors = new Hash();
    ok(!val.validate(fields, errors), "should fail validation");
    is(errors.get("nr1"), null, "no error for nr1");
    is(errors.get("nr2"), null, "no error for nr2");
    is(errors.get("r1"), "Required1 is required", "check error for r1");
    is(errors.get("r2"), "Required2 is required", "check error for r2");
    is(errors.get("r3"), null, "no error for r3");
  }

  {
    // confirm
    var fields = new Hash({
      password: new TestField({
	name: "password",
	value: "abc",
	description: "Password",
	rules: "",
	required: true
      }),
      confirm: new TestField({
	name: "confirm",
	value: "abc",
	description: "Confirm",
	rules: "confirm:password",
      }),
      confirm2: new TestField({
	name: "confirm2",
	value: "abcd",
	description: "Confirm2",
	rules: "confirm:password",
      })
    });
    var val = new BSEValidator();
    var errors = new Hash();
    val.validate(fields, errors);
    is(errors.get("confirm"), null, "should be no error for confirm");
    is(errors.get("confirm2"), "Confirm2 must be the same as Password",
       "confirm2 should have an error");
  }

  tests_done();
});