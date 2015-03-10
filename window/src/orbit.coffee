# Utility functions and constants
TWO_PI = 2 * Math.PI
HALF_PI = 0.5 * Math.PI

sign = (x) ->
  if typeof x == 'number' # JIT compiler hint
    if x
      if x < 0 then -1 else 1
    else
      if x == x then 0 else NaN
  else
    NaN

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

normalize = (v) -> numeric.divVS(v, numeric.norm2(v))

projectToPlane = (p, n) -> numeric.subVV(p, numeric.mulSV(numeric.dotVV(p, n), n))

angleInPlane = (from, to, normal) ->
  from = normalize(projectToPlane(from, normal))
  to = normalize(projectToPlane(to, normal))
  rot = quaternion.fromToRotation(normal, [0, 0, 1])
  from = quaternion.rotate(rot, from)
  to = quaternion.rotate(rot, to)
  result = Math.atan2(from[1], from[0]) - Math.atan2(to[1], to[0])
  if result < 0 then result + TWO_PI else result

newtonsMethod = roots.newtonsMethod
brentsMethod = roots.brentsMethod
goldenSectionSearch = roots.goldenSectionSearch

(exports ? this).Orbit = class Orbit
  constructor: (@referenceBody, @semiMajorAxis, @eccentricity, inclination,
    longitudeOfAscendingNode, argumentOfPeriapsis, @meanAnomalyAtEpoch, @timeOfPeriapsisPassage) ->
    @inclination = inclination * Math.PI / 180 if inclination?
    @longitudeOfAscendingNode = longitudeOfAscendingNode * Math.PI / 180 if longitudeOfAscendingNode?
    @argumentOfPeriapsis = argumentOfPeriapsis * Math.PI / 180 if argumentOfPeriapsis?
  
  isHyperbolic: ->
    @eccentricity > 1
  
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
    a = Math.abs(@semiMajorAxis)
    Math.sqrt(@referenceBody.gravitationalParameter / (a * a * a))
  
  period: ->
    if @isHyperbolic() then Infinity else TWO_PI / @meanMotion()
    
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
    p2 = numeric.subVV(p2, numeric.mulVS(n, numeric.dotVV(p2, n))) # Project p2 onto our orbital plane
    r1 = numeric.norm2(p1)
    r2 = numeric.norm2(p2)
    phaseAngle = Math.acos(numeric.dotVV(p1, p2) / (r1 * r2))
    phaseAngle = TWO_PI - phaseAngle if numeric.dotVV(crossProduct(p1, p2), n) < 0
    phaseAngle = phaseAngle - TWO_PI if orbit.semiMajorAxis < @semiMajorAxis
    phaseAngle
    
  # Orbital state at time t
  
  meanAnomalyAt: (t) ->
    if @isHyperbolic()
      (t - @timeOfPeriapsisPassage) * @meanMotion()
    else
      if @timeOfPeriapsisPassage?
        M = ((t - @timeOfPeriapsisPassage) % @period()) * @meanMotion()
        if M < 0 then M + TWO_PI else M
      else
        (@meanAnomalyAtEpoch + @meanMotion() * (t % @period())) % TWO_PI
  
  eccentricAnomalyAt: (t) ->
    e = @eccentricity
    M = @meanAnomalyAt(t)
    
    if @isHyperbolic()
      newtonsMethod M,
        (x) -> M - e * sinh(x) + x
        (x) -> 1 - e * cosh(x)
    else
      newtonsMethod M,
        (x) -> M + e * Math.sin(x) - x
        (x) -> e * Math.cos(x) - 1
  
  trueAnomalyAt: (t) ->
    e = @eccentricity
    if @isHyperbolic()
      H = @eccentricAnomalyAt(t)
      tA = Math.acos((e - cosh(H)) / (cosh(H) * e - 1))
      if H < 0 then -tA else tA
    else
      E = @eccentricAnomalyAt(t)
      tA = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(E / 2), Math.sqrt(1 - e) * Math.cos(E / 2))
      if tA < 0 then tA + TWO_PI else tA
    
  # Orbital state at true anomaly
  
  eccentricAnomalyAtTrueAnomaly: (tA) ->
    e = @eccentricity
    if @isHyperbolic()
      cosTrueAnomaly = Math.cos(tA)
      H = acosh((e + cosTrueAnomaly) / (1 + e * cosTrueAnomaly))
      if tA < 0 then -H else H
    else
      E = 2 * Math.atan(Math.tan(tA/2) / Math.sqrt((1 + e) / (1 - e)))
      if E < 0 then E + TWO_PI else E
  
  meanAnomalyAtTrueAnomaly: (tA) ->
    e = @eccentricity
    if @isHyperbolic()
      H = @eccentricAnomalyAtTrueAnomaly(tA)
      e * sinh(H) - H
    else
      E = @eccentricAnomalyAtTrueAnomaly(tA)
      E - e * Math.sin(E)
  
  timeAtTrueAnomaly: (tA, t0 = 0) ->
    M = @meanAnomalyAtTrueAnomaly(tA)
    if @isHyperbolic()
      @timeOfPeriapsisPassage + M / @meanMotion() # Eq. 4.86
    else
      p = @period()
      if @timeOfPeriapsisPassage?
        t = @timeOfPeriapsisPassage + p * Math.floor((t0 - @timeOfPeriapsisPassage) / p) + M / @meanMotion()
      else
        t = (t0 - (t0 % p)) + (M - @meanAnomalyAtEpoch) / @meanMotion()
      if t < t0 then t + p else t
  
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
  
  trueAnomalyAtPosition: (p) ->
    p = quaternion.rotate(quaternion.conjugate(@rotationToReferenceFrame()), p)
    Math.atan2(p[1], p[0])


Orbit.fromJSON = (json) ->
  referenceBody = CelestialBody.fromJSON(json.referenceBody)
  result = new Orbit(referenceBody, json.semiMajorAxis, json.eccentricity)
  result.inclination = json.inclination
  result.longitudeOfAscendingNode = json.longitudeOfAscendingNode
  result.argumentOfPeriapsis = json.argumentOfPeriapsis
  result.meanAnomalyAtEpoch = json.meanAnomalyAtEpoch
  result.timeOfPeriapsisPassage = json.timeOfPeriapsisPassage
  result
  
Orbit.fromApoapsisAndPeriapsis = (referenceBody, apoapsis, periapsis, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch, timeOfPeriapsisPassage) ->
  [apoapsis, periapsis] = [periapsis, apoapsis] if apoapsis < periapsis
  semiMajorAxis = (apoapsis + periapsis) / 2
  eccentricity = apoapsis / semiMajorAxis - 1
  new Orbit(referenceBody, semiMajorAxis, eccentricity, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch, timeOfPeriapsisPassage)

Orbit.fromPositionAndVelocity = (referenceBody, position, velocity, t) ->
  # From: http://www.braeunig.us/space/interpl.htm#elements
  mu = referenceBody.gravitationalParameter
  r = numeric.norm2(position)
  v = numeric.norm2(velocity)
  
  specificAngularMomentum = crossProduct(position, velocity) # Eq. 5.21
  if specificAngularMomentum[0] != 0 or specificAngularMomentum[1] != 0
    nodeVector = normalize([-specificAngularMomentum[1], specificAngularMomentum[0], 0]) # Eq. 5.22
  else
    nodeVector = [1, 0, 0]
  eccentricityVector = numeric.mulSV(1 / mu, numeric.subVV(numeric.mulSV(v*v - mu / r, position), numeric.mulSV(numeric.dotVV(position, velocity), velocity))) # Eq. 5.23
  
  semiMajorAxis = 1 / (2 / r - v * v / mu) # Eq. 5.24
  eccentricity = numeric.norm2(eccentricityVector) # Eq. 5.25
  orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity)
  
  orbit.inclination = Math.acos(specificAngularMomentum[2] / numeric.norm2(specificAngularMomentum)) # Eq. 5.26
  if eccentricity == 0
    orbit.argumentOfPeriapsis = 0
    orbit.longitudeOfAscendingNode = 0
  else
    orbit.longitudeOfAscendingNode = Math.acos(nodeVector[0]) # Eq. 5.27
    orbit.longitudeOfAscendingNode = TWO_PI - orbit.longitudeOfAscendingNode if nodeVector[1] < 0
    orbit.argumentOfPeriapsis = Math.acos(numeric.dotVV(nodeVector, eccentricityVector) / eccentricity) # Eq. 5.28
    orbit.argumentOfPeriapsis = TWO_PI - orbit.argumentOfPeriapsis if eccentricityVector[2] < 0
  
  trueAnomaly = Math.acos(numeric.dotVV(eccentricityVector, position) / (eccentricity * r)) # Eq. 5.29
  trueAnomaly = -trueAnomaly if numeric.dotVV(position, velocity) < 0
  
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.timeOfPeriapsisPassage = t - meanAnomaly / orbit.meanMotion()
  
  orbit

circularToEscapeDeltaV = (body, v0, vsoi, relativeInclination) ->
  mu = body.gravitationalParameter
  rsoi = body.sphereOfInfluence
  v1 = Math.sqrt(vsoi * vsoi + 2 * v0 * v0 - 2 * mu / rsoi) # Eq 4.15 Velocity at periapsis

  r0 = mu / (v0 * v0)
  e = r0 * v1 * v1 / mu - 1 # Ejection orbit eccentricity
  ap = r0 * (1 + e) / (1 - e) # Ejection orbit apoapsis
  if ap > 0 and ap <= rsoi
    return NaN # There is no orbit that leaves the SoI with a velocity of vsoi

  if relativeInclination
    Math.sqrt(v0 * v0 + v1 * v1 - 2 * v0 * v1 * Math.cos(relativeInclination)) # Eq. 4.74
  else
    v1 - v0 # Eq. 5.36

insertionToCircularDeltaV = (body, vsoi, v0) ->
  mu = body.gravitationalParameter
  rsoi = body.sphereOfInfluence
  Math.sqrt(vsoi * vsoi + 2 * v0 * v0 - 2 * mu / rsoi) - v0 # Eq 4.15 Velocity at periapsis

ejectionAngle = (vsoi, theta, prograde) ->
  # Normalize and componentize the soi velocity vector
  [ax, ay, az] = normalize(vsoi)
  cosTheta = Math.cos(theta)
  
  # We have two equations of two unknowns (vx, vy):
  #   dot(v, vsoi) = cosTheta
  #   norm(v) = 1  [Unit vector]
  #   vz = 0  [Perpendicular to z-axis]
  #
  # Solution is defined iff:
  #   ay != 0 [because we are solving for vx first]
  
  # Intermediate terms
  g = -ax / ay
  
  # Quadratic coefficients
  a = 1 + g * g
  b = 2 * g * cosTheta / ay
  c = cosTheta * cosTheta / (ay * ay) - 1
  
  # Quadratic formula without loss of significance (Numerical Recipes eq. 5.6.4)
  if b < 0
    q = -0.5 * (b - Math.sqrt(b * b - 4 * a * c))
  else
    q = -0.5 * (b + Math.sqrt(b * b - 4 * a * c))
    
  # Solution
  vx = q / a
  vy = g * vx + cosTheta / ay
  
  if sign(crossProduct([vx, vy, 0], [ax, ay, az])[2]) != sign(Math.PI - theta) # Wrong orbital direction
    vx = c / q
    vy = g * vx + cosTheta / ay
  
  prograde = [prograde[0], prograde[1], 0] # Project the prograde vector onto the XY plane
  if crossProduct([vx, vy, 0], prograde)[2] < 0
    TWO_PI - Math.acos(numeric.dotVV([vx, vy, 0], prograde))
  else
    Math.acos(numeric.dotVV([vx, vy, 0], prograde))

Orbit.transfer = (transferType, originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity, p0, v0, n0, p1, v1, planeChangeAngleToIntercept) ->
  # Fill in missing values
  referenceBody = originBody.orbit.referenceBody
  t1 = t0 + dt
  unless p0? and v0?
    nu0 = originBody.orbit.trueAnomalyAt(t0)
    p0 ?= originBody.orbit.positionAtTrueAnomaly(nu0)
    v0 ?= originBody.orbit.velocityAtTrueAnomaly(nu0)
  unless p1? and v1?
    nu1 = destinationBody.orbit.trueAnomalyAt(t1)
    p1 ?= destinationBody.orbit.positionAtTrueAnomaly(nu1)
    v1 ?= destinationBody.orbit.velocityAtTrueAnomaly(nu1)
  n0 ?= originBody.orbit.normalVector()
  
  if transferType == "optimal"
    ballisticTransfer = Orbit.transfer("ballistic", originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity, p0, v0, n0, p1, v1)
    return ballisticTransfer if ballisticTransfer.angle <= HALF_PI
    planeChangeTransfer = Orbit.transfer("optimalPlaneChange", originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity, p0, v0, n0, p1, v1)
    return if ballisticTransfer.deltaV < planeChangeTransfer.deltaV then ballisticTransfer else planeChangeTransfer
  else if transferType == "optimalPlaneChange"
    if numeric.norm2(p0) > numeric.norm2(p1)
      # Transferring to a lower orbit, optimum time to change inclination is 90 degrees to intercept or sooner
      x1 = HALF_PI
      x2 = Math.PI
    else
      # Transferring to a higher orbit, the optimum time to change inclination is 90 degrees to intercept or later
      x1 = 0
      x2 = HALF_PI
    
    # This calculates an approximation of the optimal angle to intercept to perform the plane change.
    # The approximation does not take into account the change in the transfer orbit due to the change
    # in the target position rotated into the origin plane as the plane change axis changes.
    # This approximation should be valid so long as the transfer orbit's semi-major axis and eccentricity
    # does not change significantly with the change in the plane change axis.
    relativeInclination = Math.asin(numeric.dotVV(p1, n0) / numeric.norm2(p1))
    planeChangeRotation = quaternion.fromAngleAxis(-relativeInclination, crossProduct(p1, n0))
    p1InOriginPlane = quaternion.rotate(planeChangeRotation, p1)
    v1InOriginPlane = quaternion.rotate(planeChangeRotation, v1)
    ejectionVelocity = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)[0][0]
    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    trueAnomalyAtIntercept = orbit.trueAnomalyAtPosition(p1InOriginPlane)
    x = goldenSectionSearch x1, x2, 1e-2, (x) ->
      planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
      Math.abs(2 * orbit.speedAtTrueAnomaly(trueAnomalyAtIntercept - x) * Math.sin(0.5 * planeChangeAngle))

    # Refine the initial estimate by running the algorithm again
    planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
    planeChangeAxis = quaternion.rotate(quaternion.fromAngleAxis(-x, n0), projectToPlane(p1, n0))
    planeChangeRotation = quaternion.fromAngleAxis(planeChangeAngle, planeChangeAxis)
    p1InOriginPlane = quaternion.rotate(planeChangeRotation, p1)
    v1InOriginPlane = quaternion.rotate(planeChangeRotation, v1)
    ejectionVelocity = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)[0][0]
    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    trueAnomalyAtIntercept = orbit.trueAnomalyAtPosition(p1InOriginPlane)
    x = goldenSectionSearch x1, x2, 1e-2, (x) ->
      planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
      Math.abs(2 * orbit.speedAtTrueAnomaly(trueAnomalyAtIntercept - x) * Math.sin(0.5 * planeChangeAngle))
    
    return Orbit.transfer("planeChange", originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity, p0, v0, n0, p1, v1, x)
  else if transferType == "planeChange"
    planeChangeAngleToIntercept ?= HALF_PI
    relativeInclination = Math.asin(numeric.dotVV(p1, n0) / numeric.norm2(p1))
    planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(planeChangeAngleToIntercept))
    if planeChangeAngle != 0
      planeChangeAxis = quaternion.rotate(quaternion.fromAngleAxis(-planeChangeAngleToIntercept, n0), projectToPlane(p1, n0))
      planeChangeRotation = quaternion.fromAngleAxis(planeChangeAngle, planeChangeAxis)
      p1InOriginPlane = quaternion.rotate(quaternion.conjugate(planeChangeRotation), p1)
  
  # Assume a counter-clockwise transfer around the +z axis
  transferAngle = Math.acos(numeric.dotVV(p0, p1) / (numeric.norm2(p0) * numeric.norm2(p1)))
  transferAngle = TWO_PI - transferAngle if p0[0] * p1[1] - p0[1] * p1[0] < 0 # (p0 x p1).z

  if !planeChangeAngle or transferAngle <= HALF_PI
    solutions = lambert(referenceBody.gravitationalParameter, p0, p1, dt, 10)
    minDeltaV = Infinity
    for s in solutions
      dv = numeric.norm2(numeric.subVV(s[0], v0))
      dv += numeric.norm2(numeric.subVV(s[1], v1)) if finalOrbitVelocity?
      if dv < minDeltaV
        minDeltaV = dv
        [ejectionVelocity, insertionVelocity, transferAngle] = s
    planeChangeDeltaV = 0
  else
    [ejectionVelocity, insertionVelocity] = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)[0]

    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    planeChangeTrueAnomaly = orbit.trueAnomalyAt(t1) - planeChangeAngleToIntercept
    planeChangeDeltaV = Math.abs(2 * orbit.speedAtTrueAnomaly(planeChangeTrueAnomaly) * Math.sin(planeChangeAngle / 2))
    planeChangeDeltaV = 0 if isNaN(planeChangeDeltaV)
    planeChangeTime = orbit.timeAtTrueAnomaly(planeChangeTrueAnomaly, t0)
    insertionVelocity = quaternion.rotate(planeChangeRotation, insertionVelocity)
  
  ejectionDeltaVector = numeric.subVV(ejectionVelocity, v0)
  ejectionDeltaV = numeric.norm2(ejectionDeltaVector) # This is actually the hyperbolic excess velocity if ejecting from a parking orbit
  ejectionInclination = Math.asin(ejectionDeltaVector[2] / ejectionDeltaV)
  if initialOrbitalVelocity
    ejectionDeltaV = circularToEscapeDeltaV(originBody, initialOrbitalVelocity, ejectionDeltaV, ejectionInclination)

  if finalOrbitalVelocity?
    insertionDeltaVector = numeric.subVV(insertionVelocity, v1)
    insertionDeltaV = numeric.norm2(insertionDeltaVector) # This is actually the hyperbolic excess velocity if inserting into a parking orbit
    insertionInclination = Math.asin(insertionDeltaVector[2] / insertionDeltaV)
    if finalOrbitalVelocity
      insertionDeltaV = insertionToCircularDeltaV(destinationBody, insertionDeltaV, finalOrbitalVelocity)
  else
    insertionDeltaV = 0
  
  return {
    angle: transferAngle
    orbit: orbit
    ejectionVelocity: ejectionVelocity
    ejectionDeltaVector: ejectionDeltaVector
    ejectionInclination: ejectionInclination
    ejectionDeltaV: ejectionDeltaV
    planeChangeAngleToIntercept: planeChangeAngleToIntercept
    planeChangeDeltaV: planeChangeDeltaV
    planeChangeTime: planeChangeTime
    planeChangeAngle: if planeChangeTime? then planeChangeAngle else 0
    insertionVelocity: insertionVelocity
    insertionInclination: insertionInclination
    insertionDeltaV: insertionDeltaV
    deltaV: ejectionDeltaV + planeChangeDeltaV + insertionDeltaV
  }

Orbit.transferDetails = (transfer, originBody, t0, initialOrbitalVelocity) ->
  referenceBody = originBody.orbit.referenceBody
  nu0 = originBody.orbit.trueAnomalyAt(t0)
  p0 = originBody.orbit.positionAtTrueAnomaly(nu0)
  v0 = originBody.orbit.velocityAtTrueAnomaly(nu0)
  
  transfer.orbit ?= Orbit.fromPositionAndVelocity(referenceBody, p0, transfer.ejectionVelocity, t0)
  
  ejectionDeltaVector = transfer.ejectionDeltaVector
  ejectionInclination = transfer.ejectionInclination
  
  if initialOrbitalVelocity
    # Ejection delta-v components
    mu = originBody.gravitationalParameter
    rsoi = originBody.sphereOfInfluence
    vsoi = numeric.norm2(ejectionDeltaVector)
    v1 = Math.sqrt(vsoi * vsoi + 2 * initialOrbitalVelocity * initialOrbitalVelocity - 2 * mu / rsoi) # Eq 4.15 Velocity at periapsis
    transfer.ejectionNormalDeltaV = v1 * Math.sin(ejectionInclination)
    transfer.ejectionProgradeDeltaV = v1 * Math.cos(ejectionInclination) - initialOrbitalVelocity
    transfer.ejectionHeading = Math.atan2(transfer.ejectionProgradeDeltaV, transfer.ejectionNormalDeltaV)
    
    # Ejection angle to prograde
    initialOrbitRadius = mu / (initialOrbitalVelocity * initialOrbitalVelocity)
    e = initialOrbitRadius * v1 * v1 / mu - 1 # Ejection orbit eccentricity
    a = initialOrbitRadius / (1 - e) # Ejection orbit semi-major axis
    theta = Math.acos((a * (1 - e * e) - rsoi) / (e * rsoi)) # Eq. 4.82 True anomaly at SOI
    theta += Math.asin(v1 * initialOrbitRadius / (vsoi * rsoi)) # Eq 4.23 Zenith angle at SOI
    transfer.ejectionAngle = ejectionAngle(ejectionDeltaVector, theta, normalize(v0))
  else
    ejectionDeltaV = transfer.ejectionDeltaV
    positionDirection = numeric.divVS(p0, numeric.norm2(p0))
    progradeDirection = numeric.divVS(v0, numeric.norm2(v0))
    n0 = originBody.orbit.normalVector()
    burnDirection = numeric.divVS(ejectionDeltaVector, ejectionDeltaV)
    
    transfer.ejectionPitch = Math.asin(numeric.dotVV(burnDirection, positionDirection))
    transfer.ejectionHeading = angleInPlane([0,0,1], burnDirection, positionDirection)
    
    progradeDeltaV = numeric.dotVV(ejectionDeltaVector, progradeDirection)
    normalDeltaV = numeric.dotVV(ejectionDeltaVector, n0)
    radialDeltaV = Math.sqrt(ejectionDeltaV*ejectionDeltaV - progradeDeltaV*progradeDeltaV - normalDeltaV*normalDeltaV)
    radialDeltaV = -radialDeltaV if numeric.dotVV(crossProduct(burnDirection, progradeDirection), n0) < 0
    
    transfer.ejectionProgradeDeltaV = progradeDeltaV
    transfer.ejectionNormalDeltaV = normalDeltaV
    transfer.ejectionRadialDeltaV = radialDeltaV

  transfer
  
Orbit.refineTransfer = (transfer, transferType, originBody, destinationBody, t0, dt, initialOrbitalVelocity, finalOrbitalVelocity) ->
  return transfer unless initialOrbitalVelocity
  
  for i in [1..10]
    return transfer if isNaN(transfer.deltaV)
    unless transfer.ejectionAngle?
      transfer = Orbit.transferDetails(transfer, originBody, t0, initialOrbitalVelocity)
    
    # Calculate the ejection orbit
    mu = originBody.gravitationalParameter
    rsoi = originBody.sphereOfInfluence
    vsoi = numeric.norm2(transfer.ejectionDeltaVector)
    v1 = Math.sqrt(vsoi * vsoi + 2 * initialOrbitalVelocity * initialOrbitalVelocity - 2 * mu / rsoi) # Eq 4.15 Velocity at periapsis
    initialOrbitRadius = mu / (initialOrbitalVelocity * initialOrbitalVelocity)
    e = initialOrbitRadius * v1 * v1 / mu - 1 # Ejection orbit eccentricity
    a = initialOrbitRadius / (1 - e) # Ejection orbit semi-major axis
    nu = Math.acos((a * (1 - e * e) - rsoi) / (e * rsoi)) # Eq. 4.82 True anomaly at SOI
  
    originOrbit = originBody.orbit
    prograde = originOrbit.velocityAtTrueAnomaly(originOrbit.trueAnomalyAt(t0))
    longitudeOfAscendingNode = Math.atan2(prograde[1], prograde[0]) - transfer.ejectionAngle
    argumentOfPeriapsis = 0
    if transfer.ejectionInclination < 0
      longitudeOfAscendingNode -= Math.PI
      argumentOfPeriapsis = Math.PI
    longitudeOfAscendingNode += TWO_PI while longitudeOfAscendingNode < 0
  
    ejectionOrbit = new Orbit(originBody, a, e, null, null, null, null, t0)
    ejectionOrbit.inclination = transfer.ejectionInclination
    ejectionOrbit.longitudeOfAscendingNode = longitudeOfAscendingNode
    ejectionOrbit.argumentOfPeriapsis = argumentOfPeriapsis
  
    # Calculate the actual position and time of SoI exit
    t1 = ejectionOrbit.timeAtTrueAnomaly(nu, t0)
    dtFromSOI = dt - (t1 - t0) # Offset dt by the time it takes to exit the SoI
    originTrueAnomalyAtSOI = originOrbit.trueAnomalyAt(t1)
    p1 = numeric.addVV(ejectionOrbit.positionAtTrueAnomaly(nu), originOrbit.positionAtTrueAnomaly(originTrueAnomalyAtSOI))
    originVelocityAtSOI = originOrbit.velocityAtTrueAnomaly(originTrueAnomalyAtSOI)
  
    # Create a fake orbit from the position at SoI exit and the origin velocity at time of SoI exit
    orbit = Orbit.fromPositionAndVelocity(originOrbit.referenceBody, p1, originVelocityAtSOI, t1)
    tempBody = new CelestialBody(null, null, null, orbit)
    
    # Re-calculate the transfer
    transfer = Orbit.transfer(transferType, tempBody, destinationBody, t1, dtFromSOI, 0, finalOrbitalVelocity, p1, originVelocityAtSOI)
    
    if i & 1
      lastEjectionDeltaVector = transfer.ejectionDeltaVector
    else
      # Take the average of the last two deltaVectors to avoid diverging series
      transfer.ejectionDeltaVector = numeric.mulSV(0.5, numeric.addVV(lastEjectionDeltaVector, transfer.ejectionDeltaVector))
      transfer.ejectionDeltaV = numeric.norm2(transfer.ejectionDeltaVector)
    
    # Modify the ejection and total delta-v to take the initial orbit into account
    transfer.orbit = Orbit.fromPositionAndVelocity(originOrbit.referenceBody, p1, transfer.ejectionVelocity, t1)
    transfer.ejectionDeltaV = circularToEscapeDeltaV(originBody, initialOrbitalVelocity, transfer.ejectionDeltaV, transfer.ejectionInclination)
    transfer.deltaV = transfer.ejectionDeltaV + transfer.planeChangeDeltaV + transfer.insertionDeltaV
  
  transfer

Orbit.courseCorrection = (transferOrbit, destinationOrbit, burnTime, eta) ->
  # Assumes transferOrbit already passes "close" to the destination body at eta
  mu = transferOrbit.referenceBody.gravitationalParameter
  trueAnomaly = transferOrbit.trueAnomalyAt(burnTime)
  p0 = transferOrbit.positionAtTrueAnomaly(trueAnomaly)
  v0 = transferOrbit.velocityAtTrueAnomaly(trueAnomaly)
  n0 = transferOrbit.normalVector()
  n1 = destinationOrbit.normalVector()
  
  velocityForArrivalAt = (t1) ->
    p1 = destinationOrbit.positionAtTrueAnomaly(destinationOrbit.trueAnomalyAt(t1))
    lambert(mu, p0, p1, t1 - burnTime)[0][0]
  
  # Search for the optimal arrival time within 20% of eta
  t1Min = Math.max(0.5 * (eta - burnTime), 3600)
  t1Max = 1.5 * (eta - burnTime)
  t1 = goldenSectionSearch t1Min, t1Max, 1e-4, (t1) ->
    numeric.norm2Squared(numeric.subVV(velocityForArrivalAt(burnTime + t1), v0))
  t1 = t1 + burnTime # Convert relative flight time to arrival time
  
  correctedVelocity = velocityForArrivalAt(t1)
  deltaVector = numeric.subVV(correctedVelocity, v0)
  deltaV = numeric.norm2(deltaVector)
  
  burnDirection = numeric.divVS(deltaVector, deltaV)
  positionDirection = numeric.divVS(p0, numeric.norm2(p0))
  
  pitch = Math.asin(numeric.dotVV(burnDirection, positionDirection))
  heading = angleInPlane([0,0,1], burnDirection, positionDirection)
  
  progradeDirection = numeric.divVS(v0, numeric.norm2(v0))
  progradeDeltaV = numeric.dotVV(deltaVector, progradeDirection)
  normalDeltaV = numeric.dotVV(deltaVector, n0)
  radialDeltaV = Math.sqrt(deltaV*deltaV - progradeDeltaV*progradeDeltaV - normalDeltaV*normalDeltaV)
  radialDeltaV = -radialDeltaV if numeric.dotVV(crossProduct(burnDirection, progradeDirection), n0) < 0
  
  return {
    correctedVelocity: correctedVelocity
    deltaVector: deltaVector
    deltaV: deltaV
    pitch: pitch
    heading: heading
    progradeDeltaV: progradeDeltaV
    normalDeltaV: normalDeltaV
    radialDeltaV: radialDeltaV
    arrivalTime: t1
  }
