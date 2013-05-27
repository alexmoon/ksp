# Utility functions and constants
twoPi = 2 * Math.PI
halfPi = 0.5 * Math.PI

sinh = (angle) ->
  p = Math.exp(angle)
  (p - (1 / p)) * 0.5
  
cosh = (angle) ->
  p = Math.exp(angle)
  (p + (1 / p)) * 0.5

acosh = (n) ->
  Math.log(n + Math.sqrt(n * n - 1))

crossProduct = (a, b) ->
  r = new Array(3)
  r[0] = a[1] * b[2] - a[2] * b[1]
  r[1] = a[2] * b[0] - a[0] * b[2]
  r[2] = a[0] * b[1] - a[1] * b[0]
  r


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
    twoPi / @meanMotion()
    
  rotationToReferenceFrame: ->
    axisOfInclination = [Math.cos(-@argumentOfPeriapsis), Math.sin(-@argumentOfPeriapsis), 0]
    quaternion.concat(
      quaternion.fromAngleAxis(@longitudeOfAscendingNode + @argumentOfPeriapsis, [0, 0, 1]),
      quaternion.fromAngleAxis(@inclination, axisOfInclination))
  
  normalVector: ->
    quaternion.rotate(@rotationToReferenceFrame(), [0, 0, 1])
  
  phaseAngle: (orbit, t) ->
    n = @normalVector()
    p1 = @positionAtTrueAnomaly(@trueAnomalyAt(t))
    p2 = orbit.positionAtTrueAnomaly(orbit.trueAnomalyAt(t))
    p2 = numeric.subVV(p2, numeric.mulVS(n, numeric.dot(p2, n))) # Project p2 onto our orbital plane
    r1 = numeric.norm2(p1)
    r2 = numeric.norm2(p2)
    phaseAngle = Math.acos(numeric.dot(p1, p2) / (r1 * r2))
    phaseAngle = twoPi - phaseAngle if numeric.dot(crossProduct(p1, p2), n) < 0
    phaseAngle = phaseAngle - twoPi if orbit.semiMajorAxis < @semiMajorAxis
    phaseAngle
    
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
    if tA < 0 then tA + twoPi else tA
  
  # Orbital state at true anomaly
  
  eccentricAnomalyAtTrueAnomaly: (tA) ->
    E = 2 * Math.atan(Math.tan(tA/2) / Math.sqrt((1 + @eccentricity) / (1 - @eccentricity)))
    if E < 0 then E + twoPi else E
  
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
  trueAnomaly = twoPi - trueAnomaly if flightPathAngle < 0
  
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  if heading? and latitude?
    orbit.inclination = Math.acos(Math.cos(latitude) * Math.sin(heading))
    angleToAscendingNode = Math.atan(Math.tan(latitude) / Math.cos(heading))
    orbit.argumentOfPeriapsis = angleToAscendingNode - trueAnomaly
    
    if longitude?
      false # TODO: calculate longitude of ascending node
  
  orbit

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
    orbit.longitudeOfAscendingNode = twoPi - orbit.longitudeOfAscendingNode if nodeVector[1] < 0
    orbit.argumentOfPeriapsis = Math.acos(numeric.dot(nodeVector, eccentricityVector) / (n * eccentricity)) # Eq. 5.28
    orbit.argumentOfPeriapsis = twoPi - orbit.argumentOfPeriapsis if eccentricityVector[2] < 0
  
  trueAnomaly = Math.acos(numeric.dot(eccentricityVector, position) / (eccentricity * r)) # Eq. 5.29
  trueAnomaly = twoPi - trueAnomaly if eccentricityVector[2] < 0
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  orbit
  

Orbit.circularToHyperbolicDeltaV = circularToHyperbolicDeltaV = (v0, vinf, relativeInclination) ->
  v1 = Math.sqrt(vinf * vinf + 2 * v0 * v0) # Eq. 5.35
  if relativeInclination
    Math.sqrt(v0 * v0 + v1 * v1 - 2 * v0 * v1 * Math.cos(relativeInclination)) # Eq. 4.74
  else
    v1 - v0 # Eq. 5.36
  
gaussTimeOfFlight = (mu, r1, r2, deltaNu, k, l, m, p) ->
  # From: http://www.braeunig.us/space/interpl.htm#gauss
  a = m * k * p / ((2 * m -  l * l) * p * p + 2 * k * l * p - k * k) # Eq. 5.12
  
  f = 1 - r2 / p * (1 - Math.cos(deltaNu)) # Eq. 5.5
  g = r1 * r2 * Math.sin(deltaNu) / Math.sqrt(mu * p) # Eq. 5.6
  df = Math.sqrt(mu / p) * Math.tan(deltaNu / 2) * ((1 - Math.cos(deltaNu)) / p - 1 / r1 - 1 / r2) # Eq. 5.7
  
  if a > 0
    dE = Math.acos(1 - r1 / a * (1 - f)) # Eq. 5.13
    sinDeltaE = -r1 * r2 * df / Math.sqrt(mu * a) # Eq. 5.14
    dE = twoPi - dE if sinDeltaE < 0
    g + Math.sqrt(a * a * a / mu) * (dE - sinDeltaE) # Eq. 5.16
  else
    dF = acosh(1 - r1 / a * (1 - f)) # Eq. 5.15
    g + Math.sqrt(-a * a * a / mu) * (sinh(dF) - dF) # Eq. 5.17

transferVelocities = (mu, position1, position2, dt, longWay) ->
  # From: http://www.braeunig.us/space/interpl.htm#gauss
  r1 = numeric.norm2(position1)
  r2 = numeric.norm2(position2)
  cosDeltaNu = numeric.dot(position1, position2) / (r1 * r2)
  deltaNu= Math.acos(cosDeltaNu)
  deltaNu= twoPi - deltaNu if longWay
  
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

ejectionAngle = (asymptote, eccentricity, normal, prograde) ->
  e = eccentricity
  [ax, ay, az] = numeric.divVS(asymptote, numeric.norm2(asymptote))
  [nx, ny, nz] = normal
  
  
  # We have three equations of three unknowns (vx, vy, vz):
  #   dot(v, asymptote) = cos(eta) = -1 / e  [Eq. 4.81]
  #   norm(v) = 1  [Unit vector]
  #   dot(v, normal) = 0  [Perpendicular to normal]
  #
  # Solution is defined iff:
  #   nz != 0
  #   ay != 0 or (az != 0 and ny != 0) [because we are solving for vx first]
  #   asymptote is not parallel to normal
  
  # Intermediate terms
  f = ay - az * ny / nz
  g = (az * nx - ax * nz) / (ay * nz - az * ny)
  h = (nx + g * ny) / nz
  
  # Quadratic coefficients
  a = (1 + g * g + h * h)
  b = -2 * (g * (ny * ny + nz * nz) + nx * ny) / (e * f * nz * nz)
  c = (nz * nz + ny * ny) / (e * e * f * f * nz * nz) - 1
  
  # Solution
  vx = (-b + Math.sqrt(b * b - 4 * a * c)) / (2 * a)
  vy = g * vx - 1 / (e * f)
  vz = -(vx * nx + vy * ny) / nz
  
  if numeric.dot(crossProduct([vx, vy, vz], [ax, ay, az]), normal) < 0 # Wrong orbital direction
    vx = (-b - Math.sqrt(b * b - 4 * a * c)) / (2 * a)
    vy = g * vx - 1 / (e * f)
    vz = -(vx * nx + vy * ny) / nz
  
  if numeric.dot(crossProduct([vx, vy, vz], prograde), normal) < 0
    twoPi - Math.acos(numeric.dot([vx, vy, vz], prograde))
  else
    Math.acos(numeric.dot([vx, vy, vz], prograde))

Orbit.ballisticTransfer = (referenceBody, t0, p0, v0, n0, t1, p1, v1, n1, initialOrbitalVelocity, finalOrbitalVelocity, originBody) ->
  dt = t1 - t0
  
  # TODO: Use heuristic so we don't have to calculate both transfer directions
  # (e.g. if angle is < 170 or > 190 then only go clockwise)
  shortTransfer = {}
  longTransfer = {}
  for transfer in [shortTransfer, longTransfer]
    [ejectionVelocity, insertionVelocity] =
      transferVelocities(referenceBody.gravitationalParameter, p0, p1, dt, (transfer == longTransfer))
    
    ejectionDeltaVector = numeric.subVV(ejectionVelocity, v0)
    ejectionDeltaV = numeric.norm2(ejectionDeltaVector) # This is actually the hyperbolic excess velocity if ejecting from a parking orbit
    if initialOrbitalVelocity
      ejectionInclination = halfPi - Math.acos(numeric.dot(ejectionDeltaVector, n0) / ejectionDeltaV)
      ejectionDeltaV = circularToHyperbolicDeltaV(initialOrbitalVelocity, ejectionDeltaV, ejectionInclination)
    
    if finalOrbitalVelocity?
      insertionDeltaVector = numeric.subVV(insertionVelocity, v1)
      insertionDeltaV = numeric.norm2(insertionDeltaVector) # This is actually the hyperbolic excess velocity if inserting into a parking orbit
      if finalOrbitalVelocity != 0
        insertionInclination = halfPi - Math.acos(numeric.dot(insertionDeltaVector, n1) / insertionDeltaV)
        insertionDeltaV = circularToHyperbolicDeltaV(finalOrbitalVelocity, insertionDeltaV, 0)
    else
      insertionDeltaV = 0
    
    transfer.ejectionVelocity = ejectionVelocity
    transfer.ejectionDeltaVector = ejectionDeltaVector
    transfer.ejectionInclination = ejectionInclination
    transfer.ejectionDeltaV = ejectionDeltaV
    transfer.insertionVelocity = insertionVelocity
    transfer.insertionInclination = insertionInclination
    transfer.insertionDeltaV = insertionDeltaV
    transfer.deltaV = ejectionDeltaV + insertionDeltaV
      
  transfer = if shortTransfer.deltaV < longTransfer.deltaV then shortTransfer else longTransfer
  
  if originBody # We calculate more details of the transfer if an originBody is provided
    transferAngle = Math.acos(numeric.dot(p0, p1) / (numeric.norm2(p0) * numeric.norm2(p1)))
    transferAngle = twoPi - transferAngle if transfer == longTransfer
    
    # Ejection angle to prograde
    mu = originBody.gravitationalParameter
    r = mu / (initialOrbitalVelocity * initialOrbitalVelocity)
    v = initialOrbitalVelocity + transfer.ejectionDeltaV
    e = r * v * v / mu - 1 # Eq. 4.30 simplified for a flight path angle of 0
    transfer.ejectionAngle = ejectionAngle(transfer.ejectionDeltaVector, e, n0, numeric.divVS(v0, numeric.norm2(v0)))
    
    transfer.orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, transfer.ejectionVelocity, t0)
    transfer.angle = transferAngle
  
  transfer
  
# Get universal time from altitude of two (or more) celestial bodies with eccentric orbits
# Create porkchop plot for interplanetary transfers
