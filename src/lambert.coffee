TWO_PI = 2 * Math.PI
HALF_PI = 0.5 * Math.PI

MACHINE_EPSILON = 1.0
MACHINE_EPSILON *= 0.5 until (1.0 + MACHINE_EPSILON) == 1.0

acot = (x) -> HALF_PI - Math.atan(x)
acoth = (x) -> 0.5 * Math.log((x + 1) / (x - 1))

findRoot = (a, b, relativeAccuracy, f, df, ddf) ->
  c = a
  fa = f(a)
  fb = f(b)
  fc = fa
  d = b - a
  e = d
  
  i = 0
  loop
    if Math.abs(fc) < Math.abs(fb)
      a = b
      b = c
      c = a
      fa = fb
      fb = fc
      fc = fa
    
    tol = (0.5 * MACHINE_EPSILON + relativeAccuracy) * Math.abs(b)
    m = 0.5 * (c - b)
    
    return b if fb == 0 or Math.abs(m) <= tol
    throw "Brent's method failed to converge after 100 iterations" if i > 100
    
    if Math.abs(e) < tol or Math.abs(fa) <= Math.abs(fb) # Use a bisection step
      d = e = m
    else
      s = fb / fa
      
      if a == c # Use a linear interpolation step
        p = 2 * m *s
        q = 1 - s
      else # Use a parabolic interpolation step
        q = fa / fc
        r = fb / fc
        p = s * (2 * m * q * (q - r) - (b - a) * (r - 1))
        q = (q - 1) * (r - 1) * (s - 1)
      
      if p > 0
        q = -q
      else
        p = -p
      
      if 2 * p < Math.min(3 * m * q - Math.abs(tol * q), Math.abs(e * q)) # Validate interpolation
        e = d
        d = p / q
      else # Fall back to bisection
        d = e = m
    
    a = b
    fa = fb
    
    if (Math.abs(d) > tol)
      b += d
    else
      b += if m > 0 then tol else -tol
    
    fb = f(b)
    
    if (fb < 0 and fc < 0) or (fb > 0 and fc > 0)
      c = a
      fc = fa
      d = e = b - a
    
    i++
  
@lambert = (mu, pos1, pos2, dt) ->
  # Based on Sun, F.T. "On the Minium Time Trajectory and Multiple Solutions of Lambert's Problem"
  # AAS/AIAA Astrodynamics Conference, Province Town, Massachusetts, AAS 79-164, June 25-27, 1979
  r1 = numeric.norm2(pos1)
  r2 = numeric.norm2(pos2)
  
  # Intermediate terms
  deltaPos = numeric.subVV(pos2, pos1)
  c = numeric.norm2(deltaPos)
  m = r1 + r2 + c
  n = r1 + r2 - c
  
  # Assume we want a prograde orbit counter-clockwise around the +z axis
  transferAngle = Math.acos(numeric.dot(pos1, pos2) / (r1 * r2))
  transferAngle = TWO_PI - transferAngle if pos1[0] * pos2[1] - pos1[1] * pos2[0] < 0 # (pos1 x pos2).z
  
  cosHalfTransferAngle = Math.cos(transferAngle / 2)
  angleParameter = Math.sqrt(4 * r1 * r2 / (m * m) * cosHalfTransferAngle * cosHalfTransferAngle)
  angleParameter = -angleParameter if transferAngle > Math.PI
  
  normalizedTime = 4 * dt * Math.sqrt(mu / (m * m * m))
  parabolicNormalizedTime = 2 / 3 * (1 - angleParameter * angleParameter * angleParameter)
  minimumEnergyNormalizedTime = Math.acos(angleParameter) + angleParameter * Math.sqrt(1 - angleParameter * angleParameter)
  
  fy = (x) -> # y = +/- sqrt(1 - sigma^2 * (1 - x^2))
    y = Math.sqrt(1 - angleParameter * angleParameter * (1 - x * x))
    if angleParameter < 0 then -y else y
  
  if normalizedTime == parabolicNormalizedTime # Parabolic solution
    x = 1.0
    y = if angleParameter < 0 then -1 else 1
  else if normalizedTime == minimumEnergyNormalizedTime  # The minimum energy elliptical solution
    x = 0.0
    y = fy(x)
  else
    # Returns the difference our desired normalizedTime and the normalized
    # time for a path parameter of x (given our angleParameter)
    # Defined over the domain of (-1, infinity)
    ftau = (x) ->
      if x == 1.0 # Parabolic
        parabolicNormalizedTime - normalizedTime
      else
        y = fy(x)
      
        if x > 1 # Hyperbolic
          g = Math.sqrt(x * x - 1)
          h = Math.sqrt(y * y - 1)
          (-acoth(x / g) + acoth(y / h) + x * g - y * h) / (g * g * g) - normalizedTime
        else # Elliptical: -1 < x < 1
          g = Math.sqrt(1 - x * x)
          h = Math.sqrt(1 - y * y)
          (acot(x / g) - Math.atan(h / y) - x * g + y * h) / (g * g * g) - normalizedTime
    
    # Select our bounds based on the relationship between
    # the known normalized times and our target
    if normalizedTime > parabolicNormalizedTime # Elliptical solution
      if normalizedTime < minimumEnergyNormalizedTime  # Low path
        x1 = 0.0
        x2 = 1.0
      else # High path
        x1 = -1.0 + MACHINE_EPSILON # Avoid the signularity at ftau(-1)
        x2 = 0.0
    else # Hyperbolic solution
      x1 = 1.0
      x2 = 2.0
      x2 *= 2.0 until ftau(x2) < 0.0 # Exponential search to find our upper hyperbolic bound
    
    x = findRoot(x1, x2, 1e-4, ftau)
    y = fy(x)
  
  sqrtMu = Math.sqrt(mu)
  invSqrtM = 1 / Math.sqrt(m)
  invSqrtN = 1 / Math.sqrt(n)
  
  vc = sqrtMu * (y * invSqrtN + x * invSqrtM)
  vr = sqrtMu * (y * invSqrtN - x * invSqrtM)
  ec = numeric.mulVS(deltaPos, vc / c)
  v1 = numeric.addVV(ec, numeric.mulVS(pos1, vr / r1))
  v2 = numeric.subVV(ec, numeric.mulVS(pos2, vr / r2))
  
  [v1, v2]
