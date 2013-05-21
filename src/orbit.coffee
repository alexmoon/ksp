# Hyperbolic trig functions
sinh = (angle) ->
  p = Math.exp(angle)
  (p - (1 / p)) * 0.5
  
cosh = (angle) ->
  p = Math.exp(angle)
  (p + (1 / p)) * 0.5

acosh = (n) ->
  Math.log(n + Math.sqrt(n * n - 1))

clamp = (n, min, max) -> Math.max(min, Math.min(n, max))


(exports ? this).Orbit = class Orbit
  constructor: (@referenceBody, @semiMajorAxis, @eccentricity, inclination,
    longitudeOfAscendingNode, argumentOfPeriapsis, @meanAnomalyAtEpoch) ->
    @inclination = inclination * Math.PI / 180 if inclination?
    @longitudeOfAscendingNode = longitudeOfAscendingNode * Math.PI / 180 if longitudeOfAscendingNode?
    @argumentOfPeriapsis = argumentOfPeriapsis * Math.PI / 180 if argumentOfPeriapsis?
  
  apoapsis: ->
    @semiMajorAxis * (1 + @eccentricity)
  
  periapsis: ->
    @semiMajorAxis * (1 - @eccentricity)
  
  apoapsisAltitude: ->
    @apoapsis() - @referenceBody.radius
  
  periapsisAltitude: ->
    @periapsis() - @referenceBody.radius

  semiMinorAxis: ->
    e = @eccentricity
    @semiMajorAxis * Math.sqrt(1 - e * e)
  
  semiLatusRectum: ->
    e = @eccentricity
    @semiMajorAxis * (1 - e * e)
  
  meanMotion: ->
    a = @semiMajorAxis
    Math.sqrt(@referenceBody.gravitationalParameter / (a * a * a))
  
  period: ->
    2 * Math.PI / @meanMotion()
    
  rotationToReferenceFrame: ->
    axisOfInclination = [Math.cos(-@argumentOfPeriapsis), Math.sin(-@argumentOfPeriapsis), 0]
    quaternion.concat(
      quaternion.fromAngleAxis(@longitudeOfAscendingNode + @argumentOfPeriapsis, [0, 0, 1]),
      quaternion.fromAngleAxis(@inclination, axisOfInclination))
      
  # Orbital state at time t
  
  meanAnomalyAt: (t) ->
    @meanAnomalyAtEpoch + @meanMotion() * (t % @period())
  
  eccentricAnomalyAt: (t) ->
    E = M = @meanAnomalyAt(t)
    loop
      E0 = E
      E = M + @eccentricity * Math.sin(E0)
      return E if Math.abs(E - E0) < 1e-6
  
  trueAnomalyAt: (t) ->
    E = @eccentricAnomalyAt(t)
    tA = 2 * Math.atan( Math.sqrt((1 + @eccentricity) / (1 - @eccentricity)) * Math.tan(E / 2))
    if tA < 0 then tA + 2 * Math.PI else tA
  
  # Orbital state at true anomaly
  
  eccentricAnomalyAtTrueAnomaly: (tA) ->
    E = 2 * Math.atan(Math.tan(tA/2) / Math.sqrt((1 + @eccentricity) / (1 - @eccentricity)))
    if E < 0 then E + 2 * Math.PI else E
  
  meanAnomalyAtTrueAnomaly: (tA) ->
    E = @eccentricAnomalyAtTrueAnomaly(tA)
    E - @eccentricity * Math.sin(E)
  
  timeAtTrueAnomaly: (tA) ->
    @meanAnomalyAtTrueAnomaly(tA) / @meanMotion()
  
  radiusAtTrueAnomaly: (tA) ->
    e = @eccentricity
    @semiMajorAxis * (1 - e * e) / (1 + e * Math.cos(tA))
  
  altitudeAtTrueAnomaly: (tA) ->
    @radiusAtTrueAnomaly(tA) - @referenceBody.radius

  speedAtTrueAnomaly: (tA) ->
    Math.sqrt(@referenceBody.gravitationalParameter * (2 / @radiusAtTrueAnomaly(tA) - 1 / @semiMajorAxis))
  
  positionAtTrueAnomaly: (tA) ->
    r = @radiusAtTrueAnomaly(tA)
    quaternion.rotate(@rotationToReferenceFrame(), [r * Math.cos(tA), r * Math.sin(tA), 0])
    
  velocityAtTrueAnomaly: (tA) ->
    mu = @referenceBody.gravitationalParameter
    e = @eccentricity
    h = Math.sqrt( mu * @semiMajorAxis * (1 - e * e))
    r = @radiusAtTrueAnomaly(tA)
    
    sin = Math.sin(tA)
    cos = Math.cos(tA)
    
    vr = mu * e * sin / h
    vtA = h / r
    
    quaternion.rotate(@rotationToReferenceFrame(), [vr * cos - vtA * sin, vr * sin + vtA * cos, 0])

  transferDeltaV: (orbit, t1, t2) ->
    nu1 = @trueAnomalyAt(t1)
    position1 = @positionAtTrueAnomaly(nu1)
    velocity1 = @velocityAtTrueAnomaly(nu1)
    
    nu2 = orbit.trueAnomalyAt(t2)
    position2 = orbit.positionAtTrueAnomaly(nu2)
    velocity2 = orbit.velocityAtTrueAnomaly(nu2)
    
    shortWayTransferVelocities = Orbit.transferVelocities(@referenceBody, position1, position2, t2 - t1, false)
    longWayTransferVelocities = Orbit.transferVelocities(@referenceBody, position1, position2, t2 - t1, true)
    
    shortDeltaV = numeric.norm2(numeric.subVV(velocity1, shortWayTransferVelocities[0])) +
      numeric.norm2(numeric.subVV(velocity2, shortWayTransferVelocities[1]))
    longDeltaV = numeric.norm2(numeric.subVV(velocity1, longWayTransferVelocities[0])) +
      numeric.norm2(numeric.subVV(velocity2, longWayTransferVelocities[1]))
    
    # r1 = @radiusAtTrueAnomaly(nu1)
    # r2 = orbit.radiusAtTrueAnomaly(nu2)
    # if shortDeltaV < longDeltaV
    #   console.log("Transfer orbit angle", Math.acos(numeric.dot(position1, position2) / (r1 * r2)) * 180 / Math.PI)
    #   console.log("Ejection delta-v", numeric.norm2(numeric.subVV(velocity1, shortWayTransferVelocities[0])))
    #   console.log("Insertion delta-v", numeric.norm2(numeric.subVV(velocity2, shortWayTransferVelocities[1])))
    # else
    #   console.log("Transfer orbit angle", 360 - Math.acos(numeric.dot(position1, position2) / (r1 * r2)) * 180 / Math.PI)
    #   console.log("Ejection delta-v", numeric.norm2(numeric.subVV(velocity1, longWayTransferVelocities[0])))
    #   console.log("Insertion delta-v", numeric.norm2(numeric.subVV(velocity2, longWayTransferVelocities[1])))
      
    Math.min(shortDeltaV, longDeltaV)


Orbit.fromJSON = (json) ->
  result = new Orbit(json.referenceBody, json.semiMajorAxis, json.eccentricity)
  result.inclination = json.inclination
  result.longitudeOfAscendingNode = json.longitudeOfAscendingNode
  result.argumentOfPeriapsis = json.argumentOfPeriapsis
  result.meanAnomalyAtEpoch = json.meanAnomalyAtEpoch
  result
  
Orbit.fromApoapsisAndPeriapsis = (referenceBody, apoapsis, periapsis, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch) ->
  [apoapsis, periapsis] = [periapsis, apoapsis] if apoapsis < periapsis
  semiMajorAxis = (apoapsis + periapsis) / 2
  eccentricity = apoapsis / semiMajorAxis - 1
  new Orbit(referenceBody, semiMajorAxis, eccentricity, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch)

Orbit.fromAltitudeAndVelocity = (referenceBody, altitude, speed, flightPathAngle, heading, latitude, longitude, t) ->
  # Convert to standard units
  radius = referenceBody.radius + altitude
  flightPathAngle = flightPathAngle * Math.PI / 180
  heading = heading * Math.PI / 180 if heading?
  
  mu = referenceBody.gravitationalParameter
  sinPhi= Math.sin(flightPathAngle)
  cosPhi= Math.cos(flightPathAngle)
  
  semiMajorAxis = 1 / (2 / radius - speed * speed / mu)
  eccentricity = Math.sqrt(Math.pow(radius * speed * speed / mu - 1, 2) * cosPhi * cosPhi + sinPhi * sinPhi)
  
  orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity, 0, 0, 0, 0)
  
  e = eccentricity
  trueAnomaly = Math.acos((@semiMajorAxis * (1 - e * e) / radius - 1) / e)
  trueAnomaly = 2 * Math.PI - trueAnomaly if flightPathAngle < 0
  
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  if heading? and latitude?
    orbit.inclination = Math.acos(Math.cos(latitude) * Math.sin(heading))
    angleToAscendingNode = Math.atan(Math.tan(latitude) / Math.cos(heading))
    orbit.argumentOfPeriapsis = angleToAscendingNode - trueAnomaly
    
    if longitude?
      false # TODO: calculate longitude of ascending node
  
  orbit

crossProduct = (a, b) ->
  r = new Float64Array(3)
  r[0] = a[1] * b[2] - a[2] * b[1]
  r[1] = a[2] * b[0] - a[0] * b[2]
  r[2] = a[0] * b[1] - a[1] * b[0]
  r
  
Orbit.fromPositionAndVelocity = (referenceBody, position, velocity, t) ->
  # From: http://www.braeunig.us/space/interpl.htm#elements
  mu = referenceBody.gravitationalParameter
  r = numeric.norm2(position)
  v = numeric.norm2(velocity)
  
  specificAngularMomentum = crossProduct(position, velocity) # Eq. 5.21
  nodeVector = crossProduct([0, 0, 1], specificAngularMomentum) # Eq. 5.22
  n = numeric.norm2(nodeVector)
  eccentricityVector = numeric.mulSV(1 / mu, numeric.subVV(numeric.mulSV(v*v - mu / r, position), numeric.mulSV(numeric.dot(position, velocity), velocity))) # Eq. 5.23
  
  
  semiMajorAxis = 1 / (2 / r - v * v / mu) # Eq. 5.24
  eccentricity = numeric.norm2(eccentricityVector) # Eq. 5.25
  orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity)
  
  orbit.inclination = Math.acos(specificAngularMomentum[2] / numeric.norm2(specificAngularMomentum)) # Eq. 5.26
  if eccentricity == 0
    orbit.argumentOfPeriapsis = 0
    orbit.longitudeOfAscendingNode = 0
  else
    orbit.longitudeOfAscendingNode = Math.acos(nodeVector[0] / n) # Eq. 5.27
    orbit.longitudeOfAscendingNode = 2 * Math.PI - orbit.longitudeOfAscendingNode if nodeVector[1] < 0
    orbit.argumentOfPeriapsis = Math.acos(numeric.dot(nodeVector, eccentricityVector) / (n * eccentricity)) # Eq. 5.28
    orbit.argumentOfPeriapsis = 2 * Math.PI - orbit.argumentOfPeriapsis if eccentricityVector[2] < 0
  
  trueAnomaly = Math.acos(numeric.dot(eccentricityVector, position) / (eccentricity * r)) # Eq. 5.29
  trueAnomaly = 2 * Math.PI - trueAnomaly if eccentricityVector[2] < 0
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  orbit
  

gaussTimeOfFlight = (mu, r1, r2, deltaNu, k, l, m, p) ->
  # From: http://www.braeunig.us/space/interpl.htm#gauss
  a = m * k * p / ((2 * m -  l * l) * p * p + 2 * k * l * p - k * k) # Eq. 5.12
  
  f = 1 - r2 / p * (1 - Math.cos(deltaNu)) # Eq. 5.5
  g = r1 * r2 * Math.sin(deltaNu) / Math.sqrt(mu * p) # Eq. 5.6
  df = Math.sqrt(mu / p) * Math.tan(deltaNu / 2) * ((1 - Math.cos(deltaNu)) / p - 1 / r1 - 1 / r2) # Eq. 5.7
  
  if a > 0
    dE = Math.acos(1 - r1 / a * (1 - f)) # Eq. 5.13
    sinDeltaE = -r1 * r2 * df / Math.sqrt(mu * a) # Eq. 5.14
    dE = 2 * Math.PI - dE if sinDeltaE < 0
    g + Math.sqrt(a * a * a / mu) * (dE - sinDeltaE) # Eq. 5.16
  else
    dF = acosh(1 - r1 / a * (1 - f)) # Eq. 5.15
    g + Math.sqrt(-a * a * a / mu) * (sinh(dF) - dF) # Eq. 5.17

Orbit.transferVelocities = (referenceBody, position1, position2, dt, longWay) ->
  # From: http://www.braeunig.us/space/interpl.htm#gauss
  mu = referenceBody.gravitationalParameter
  r1 = numeric.norm2(position1)
  r2 = numeric.norm2(position2)
  cosDeltaNu = numeric.dot(position1, position2) / (r1 * r2)
  deltaNu= Math.acos(cosDeltaNu)
  deltaNu= 2 * Math.PI - deltaNu if longWay
  
  throw new Error("Unable find orbit between collinear points") if Math.abs(cosDeltaNu) == 1
  
  k = r1 * r2 * (1 - cosDeltaNu) # Eq. 5.9
  l = r1 + r2 # Eq. 5.10
  m = r1 * r2 * (1 + cosDeltaNu) # Eq. 5.11
  
  # TODO: Use smart initial guess with fallback to safe case
  if longWay
    p0 = k / (l - Math.sqrt(2 * m)) # Eq.5.19
    p1 = p0 * 1e-3 # This factor seems to work for all reasonable transfer orbits, extreme transfers may fail
    p0 *= 0.999999 # Avoid floating point errors
  else
    p0 = k / (l + Math.sqrt(2 * m)) # Eq. 5.18
    p1 = p0 * 1e3 # This factor seems to work for all reasonable transfer orbits, extreme transfers may fail
    p0 *= 1.000001 # Avoid floating point errors
  
  t0 = gaussTimeOfFlight(mu, r1, r2, deltaNu, k, l, m, p0)
  t1 = gaussTimeOfFlight(mu, r1, r2, deltaNu, k, l, m, p1)
  
  if t0 < dt
    p = p0
  else if t1 > dt
    p = p1
  else loop
    p = (p0 + p1) / 2
    break if p == p0 or p == p1 # We have reached floating point resolution
    t = gaussTimeOfFlight(mu, r1, r2, deltaNu, k, l, m, p)
    break if Math.abs(1 - t / dt) < 1e-6 # Close enough
    if t < dt then p1 = p else p0 = p
  
  # The next four calculations are redundant with work done in gaussTimeOfFlight()
  a = m * k * p / ((2 * m -  l * l) * p * p + 2 * k * l * p - k * k) # Eq. 5.12
  f = 1 - r2 / p * (1 - cosDeltaNu) # Eq. 5.5
  g = r1 * r2 * Math.sin(deltaNu) / Math.sqrt(mu * p) # Eq. 5.6
  df = Math.sqrt(mu / p) * Math.tan(deltaNu / 2) * ((1 - cosDeltaNu) / p - 1 / r1 - 1 / r2) # Eq. 5.7
  dg = 1 - r1 / p * (1 - cosDeltaNu) # Eq. 5.8
  
  v1 = numeric.mulVS(numeric.subVV(position2, numeric.mulVS(position1, f)), 1 / g) # Eq. 5.3
  v2 = numeric.addVV(numeric.mulVS(position1, df), numeric.mulVS(v1, dg)) # Eq. 5.4
  
  [v1, v2]

# Get universal time from altitude of two (or more) celestial bodies with eccentric orbits
# Create porkchop plot for interplanetary transfers
