// KSP Aerobraking Calculator
$(document).ready(function() {
(function() {

	this.mkPlanet = function(Rmin, Ratm, SOI, mu, H0, P0, Trot) {
		return {
			Rmin: Rmin,	// Equatorial Radius (m)
			Ratm: Ratm+Rmin,	// Atmospheric Height (m) // helps simplify calculations
			SOI: SOI,	// Sphere of influence (m)
			mu: mu,	// Grav. parameter (m3/s2) // kerbal constant
			H0: H0,	// Scale height of atmosphere (m) // P falls off by 1/e for each H0
			P0: P0,	// Pressure at zero altitude (atm)
			Trot: Trot	// Sidereal Rotation Period (s)
		};
	};

	this.Planets = {
		Eve: mkPlanet(700000,96708.574,85109365,8.1717302e12,7000,5,80500),
		Kerbin: mkPlanet(600000,69077.553,84159286,3.5316e12,5000,1,21600),
		Duna: mkPlanet(320000,41446.532,47921949,301363210000,3000,0.2,65517.859),
		Jool: mkPlanet(6000000,138155.11,2455985200,2.82528e14,10000,15,36000),
		Laythe: mkPlanet(500000,55262.042,3723645.8,1.962e12,4000,0.8,52980.879)
	};

	this.sign = function(x) { return x > 0 ? 1 : x < 0 ? -1 : 0; }

	// Simple 2D vector math implementation
	this.vmult = function( k, v ) {
		var ret = new Array();
		for (var i = 0; i < v.length; ++i) {ret[i] = v[i]*k;}
		return ret;
	};
	this.vsum = function() {
		var ret = new Array();
		for (var i = 0; i < arguments[0].length; ++i) {
			ret[i] = 0;
			for (var j = 0; j < arguments.length; ++j) {
				ret[i] += arguments[j][i];
			}
		}
		return ret;
	};
	this.vdiff = function( a, b ) {
		var ret = new Array();
		for (var i = 0; i < a.length; ++i) {ret[i] = a[i] - b[i];}
		return ret;
	};
	this.vnorm = function( v ) {
		var norm = 0;
		for (var i = 0; i < v.length; ++i) {norm += v[i]*v[i];}
		return Math.sqrt(norm);
	};
	this.vdot = function( a, b ) {
		var ret = 0;
		for (var i = 0; i < a.length; ++i) ret += a[i]*b[i];
		return ret;
	};
	this.vcross2d = function( a, b ) {	// Cross [a0 a1 0] with [b0 b1 0]
		return a[0]*b[1] - a[1]*b[0];
	};
	this.vec2 = function( x, y ) {
		return [x, y];
	};

	// Method of bisection for root finding
	this.fzero = function( f, Ain, Bin, Tol, Nmax ) {
		Tol = typeof Tol !== 'undefined' ? Tol : 1e-2;	// This is tiny relative to the values involved!
		Nmax = typeof Nmax !== 'undefined' ? Nmax : 1000;
		var N = 1,
			a = Ain,
			b = Bin,
			c,
			fc,
			fa = f(a);

		while (N < Nmax) {
			c = (a+b)/2;
			fc = f(c);	// Don't want to re-evaluate this -- it's expensive!
			if (fc == 0 || (b-a)/2<Tol) return c;
			N = N + 1;
			if (sign(fc) == sign(fa)) {
				a = c;
				fa = fc;
			} else {
				b = c;
			}
		}
		console.log('Bisection failed!');
	};

	// Physics integrator
	// Velocity-Verlet with Velocity-dependent forces
	// Terminates once atmosphere is breached OR if impact occurs.
	this.integrate_path = function( F, m, r0, v0, dt, Planet ) {
		var t = 0,
			r = r0,
			v = v0;

		var a = function(rin, vin) { return vmult(1/m, F(rin, vin)); };

		firstrun = true;

		var rold, vold, vest, a_t;

		while (firstrun || (vnorm(r) <= Planet.Ratm && vnorm(r) >= Planet.Rmin)) {
			rold = r;
			vold = v;
			a_t = a(rold, vold);
			r = vsum(rold, vmult(dt, vold), vmult(0.5*dt*dt, a_t));
			vest = vsum(vold, vmult(0.5*dt, vsum(a_t,a(r,vsum(vold,vmult(dt,a_t))))));
			v = vsum(vold, vmult(0.5*dt,vsum(a_t,a(r,vest))));
			t = t + dt;
			firstrun = false;
		}
		return {rf:r, vf:v, tf:t};
	};

	//console.log(integrate_path(my_F, 1, [0, 10], [0, 0], 0.0001, {Rmin:0, Ratm:10000}));

	// Get orbit parameters in the plane of orbit
	this.get_orbit_params = function( r, v, Planet ) {
		// sp. orbital energy
		var ep = vdot(v,v)/2 - Planet.mu/vnorm(r);
		// sp. angular momentum
		var hmag = vcross2d(r,v);

		// eccentricity
		var ec = Math.sqrt(1+2*ep*hmag*hmag/Planet.mu/Planet.mu);

		// semi-major axis
		var a = -Planet.mu/(2*ep);

		// Periapse distance
		var rpe = -a*(ec-1);

		// Apoapse distance
		var rap = (1+ec)*a;

		return {ep: ep, ec: ec, a: a, hmag: hmag, rpe: rpe, rap: rap};
	};

	// Net force in atmosphere
	this.in_atmo_force = function(d, m, A, Planet, orbitDir) {
		// Need to consider orbit direction!
		var Kp = 1.2230948554874*0.008,
			braking_functions = {
				"prograde": function(r,v) {return vdiff(v, vmult(-1,[-2.0*Math.PI/Planet.Trot*r[1], 2.0*Math.PI/Planet.Trot*r[0]]))},
				"retrograde": function(r,v) {return vdiff(v, vmult(1,[-2.0*Math.PI/Planet.Trot*r[1], 2.0*Math.PI/Planet.Trot*r[0]]))},
				"ignore": function(r,v) {return v;}
			},
			v_surface = braking_functions[orbitDir];
		return function(r,v) {return vsum(vmult(-0.5*Kp*Planet.P0*Math.exp((Planet.Rmin-vnorm(r))/Planet.H0)*vnorm(v_surface(r,v))*d*m*A, v_surface(r,v)), vmult(-m*Planet.mu/Math.pow(vnorm(r),3), r));};
	};

	var final_orbit_params;

	this.calc1 = function(dist, vx, vy, d, Planet, orbitDir) {
		var r0 = [dist, 0],
			v0 = [vx, vy],
			dt = 1,
			m = 1,
			A = 1;

		var rap_out = 0;

		var p1 = get_orbit_params( r0, v0, Planet );

		// Short-circuit tests
		if (p1.rpe < Planet.Rmin) {
			// Initial suborbital
			rap_out = Planet.Rmin;	// Technically right!
			return rap_out;
		}
		else if (p1.ep >= 0 && p1.rpe > Planet.Ratm) {
			// Initial hyperbolic (or parabolic) escape
			rap_out = Planet.SOI+1;	// Still technically right . . .
			return rap_out;
		}
		else if (p1.ep < 0 && p1.rpe > Planet.Ratm) {
			if (p1.rap < Planet.SOI) {
				// Initial stable, no atmosphere entry
				rap_out = p1.rap;
				return rap_out;
			} else {
				// Initial ep<0 SOI escape
				rap_out = Planet.SOI+1;
				return rap_out;
			}
		}
		// If we've made it this far, we're hitting the atmosphere without guarantee of impact!
		//console.log(Planet);
		// Angle from periapsis at which we contact the atmosphere.
		var theta_contact = Math.acos((1/p1.ec)*(p1.a*(1-p1.ec*p1.ec)/Planet.Ratm-1));

		// Magnitude of velocity when contacting atmosphere
		var vcontact_mag = Math.sqrt(2*(p1.ep+Planet.mu/Planet.Ratm));

		// Use conservation of angular momentum to find angle between velocity and radial position
		var theta_1 = Math.asin(p1.hmag/(Planet.Ratm*vcontact_mag));

		var rcontact = vmult(Planet.Ratm, [Math.cos(theta_contact), Math.sin(theta_contact)]);

		// The sines and cosines here have been chosen to give the velocity as [vr, vtheta]
		var vcontact = vmult(vcontact_mag, [-Math.cos(theta_1+theta_contact), -Math.sin(theta_1+theta_contact)]);

		var F = in_atmo_force( d, m, A, Planet, orbitDir );

		// Integrate path in atmosphere.
		var rvt = integrate_path(F, m, rcontact, vcontact, dt, Planet);
		//console.log(rvt.rf);
		//console.log('Aero-encounter!');
		if (vnorm(rvt.rf) >= Planet.Rmin) {// If not, we've impacted!
			var p2 = get_orbit_params(rvt.rf, rvt.vf, Planet);
			if (p2.ep < 0) {
				rap_out = (1+p2.ec)*p2.a;	// Tentative apoapse distance
				if (rap_out > Planet.SOI) { // Post aerobrake SOI escape!
					rap_out = Planet.SOI+1;
					return rap_out;
				}
				//console.log('Capture!');
			} else {
				rap_out = Planet.SOI+1;	// Parabolic or hyperbolic escape
				//console.log('Escape!');
				return rap_out;
			}
		} else {
			// Impact!
			//console.log('Impact!');
			rap_out = Planet.Rmin;
			return rap_out;
		}
		final_orbit_params = get_orbit_params(rvt.rf, rvt.vf, Planet);
		return rap_out;
	};

	// Perform calculations for a given r (scalar), v (scalar), rpe (scalar)
	this.calc_pe = function( r, v, rpe, d, Planet, orbitDir ) {
		var vy = (rpe/r)*Math.sqrt(v*v+2*Planet.mu*(1/rpe-1/r));
		var vx = Math.sqrt(v*v-vy*vy);
		var ap = calc1(r, vx, vy, d, Planet, orbitDir);
		return ap;
	};

	// Allow (optional) use of units.
	this.parseUnitFloat = function(v) {
		var v = v.toLowerCase();
		var value = parseFloat(v);
		if (v.indexOf("mm") !== -1) {
			return value * 1000000;
		} else if (v.indexOf("km") !== -1) {
			return value * 1000;
		} else {
			return value;
		}
	};

	// Main function
	// r is scalar (distance from centre of planet)
	// v is scalar (magnitude of orbital velocity)
	// rpe is scalar (periapse distance)
	// We search for a constant-velocity solution to this problem.
	this.solve = function( r, v, rpe, targ, d, Planet, orbitDir ) {
		var vy = (rpe/r)*Math.sqrt(v*v+2*Planet.mu*(1/rpe-1/r));
		var vx = Math.sqrt(v*v-vy*vy);

		var c_ap = function(pe) {return calc_pe(r,v,pe,d,Planet,orbitDir)-targ};

		var new_pe = fzero(c_ap,Planet.Rmin, Planet.Ratm);

		var vy1 = (new_pe/r)*Math.sqrt(v*v+2*Planet.mu*(1/new_pe-1/r));
		var vx1 = Math.sqrt(v*v-vy1*vy1);

		var dv = vnorm(vdiff([vx1, vy1], [vx, vy]));
		var dvtheta = Math.atan2(vy1-vy,vx1-vx);

		if (isNaN(dv) || isNaN(dvtheta) || isNaN(vnorm([vx1, vy1]))) {
			$('#inputAlt,#inputVel,#inputPE,#inputAP').parent().parent().addClass('error');
			$('#outputPE,#outputDV,#outputAng,#outputVel2,#outputCircDV').val('No Solution!');
			return;
		}

		$('#outputPE').val((new_pe-Planet.Rmin).toFixed(2));
		$('#outputDV').val(dv.toFixed(2));
		$('#outputAng').val((dvtheta*180/Math.PI).toFixed(2));
		$('#outputVel2').val((vnorm([vx1, vy1])).toFixed(2));
		$('#outputCircDV').val((Math.sqrt(Planet.mu/final_orbit_params.rap)-Math.abs(final_orbit_params.hmag / final_orbit_params.rap)).toFixed(2));
	};
	var that = this;

	$('#go').click(function() {

		$('#inputAlt,#inputVel,#inputPE,#inputAP').parent().parent().removeClass('error');

		var Planet = that.Planets[$('#inputBody').val()],
			r = parseUnitFloat($('#inputAlt').val(), 10)+Planet.Rmin,
			v = parseFloat($('#inputVel').val(), 10),
			pe = parseUnitFloat($('#inputPE').val(), 10)+Planet.Rmin,
			orbitDir = $('input[name=inputDir]:radio:checked').val(),
			d = parseFloat($('#inputD').val(), 10),
			target = parseUnitFloat($('#inputAP').val(), 10)+Planet.Rmin;

		solve(r,v,pe,target,d,Planet,orbitDir);
	});
	return this;
})();
});
