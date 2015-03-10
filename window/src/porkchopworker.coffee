importScripts('numeric-1.2.6.min.js')
importScripts('quaternion.js')
importScripts('roots.js')
importScripts('lambert.js')
importScripts('orbit.js')
importScripts('celestialbodies.js')

WIDTH = 300
HEIGHT = 300

@onmessage = (event) ->
  transferType = event.data.transferType
  originBody = CelestialBody.fromJSON(event.data.originBody)
  initialOrbitalVelocity = event.data.initialOrbitalVelocity
  destinationBody = CelestialBody.fromJSON(event.data.destinationBody)
  finalOrbitalVelocity = event.data.finalOrbitalVelocity
  earliestDeparture = event.data.earliestDeparture
  shortestTimeOfFlight = event.data.shortestTimeOfFlight
  xResolution = event.data.xScale / WIDTH
  yResolution = event.data.yScale / HEIGHT
  
  originOrbit = originBody.orbit
  destinationOrbit = destinationBody.orbit
  
  referenceBody = originOrbit.referenceBody
  n1 = originOrbit.normalVector()
  
  # Pre-calculate destination positions and velocities
  originPositions = []
  originVelocities = []
  for x in [0...WIDTH]
    departureTime = earliestDeparture + x * xResolution
    trueAnomaly = originOrbit.trueAnomalyAt(departureTime)
    originPositions[x] = originOrbit.positionAtTrueAnomaly(trueAnomaly)
    originVelocities[x] = originOrbit.velocityAtTrueAnomaly(trueAnomaly)
  
  deltaVs = new Float64Array(WIDTH * HEIGHT)
  i = 0
  minDeltaV = Infinity
  maxDeltaV = 0
  sumLogDeltaV = 0
  sumSqLogDeltaV = 0
  deltaVCount = 0
  lastProgress = 0
  for y in [0...HEIGHT]
    timeOfFlight = shortestTimeOfFlight + ((HEIGHT-1) - y) * yResolution
    
    for x in [0...WIDTH]
      departureTime = earliestDeparture + x * xResolution
      arrivalTime = departureTime + timeOfFlight
      
      p1 = originPositions[x]
      v1 = originVelocities[x]
      
      trueAnomaly = destinationOrbit.trueAnomalyAt(arrivalTime)
      p2 = destinationOrbit.positionAtTrueAnomaly(trueAnomaly)
      v2 = destinationOrbit.velocityAtTrueAnomaly(trueAnomaly)
  
      transfer = Orbit.transfer(transferType, originBody, destinationBody, departureTime, timeOfFlight, initialOrbitalVelocity, finalOrbitalVelocity, p1, v1, n1, p2, v2)
      deltaVs[i++] = deltaV = transfer.deltaV

      if deltaV < minDeltaV
        minDeltaV = deltaV
        minDeltaVPoint = { x: x, y: ((HEIGHT-1) - y) }
      
      maxDeltaV = deltaV if deltaV > maxDeltaV
      unless isNaN(deltaV)
        logDeltaV = Math.log(deltaV)
        sumLogDeltaV += logDeltaV
        sumSqLogDeltaV += logDeltaV * logDeltaV
        deltaVCount++
    
    now = Date.now()
    if now - lastProgress > 100
      postMessage(progress: (y + 1) / HEIGHT)
      lastProgress = now
  
  try
    # Try to use transferable objects first to save about 1 MB memcpy
    postMessage({ deltaVs: deltaVs.buffer, minDeltaV: minDeltaV, minDeltaVPoint: minDeltaVPoint, maxDeltaV: maxDeltaV, deltaVCount: deltaVCount, sumLogDeltaV: sumLogDeltaV, sumSqLogDeltaV: sumSqLogDeltaV }, [deltaVs.buffer])
  catch error
    # Fallback to compatible version
    postMessage({ deltaVs: deltaVs, minDeltaV: minDeltaV, minDeltaVPoint: minDeltaVPoint, maxDeltaV: maxDeltaV, deltaVCount: deltaVCount, sumLogDeltaV: sumLogDeltaV, sumSqLogDeltaV: sumSqLogDeltaV })
