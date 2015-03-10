# Utility functions and constants
GOLDEN_RATIO = (1 + Math.sqrt(5)) / 2

MACHINE_EPSILON = 1.0
MACHINE_EPSILON *= 0.5 until (1.0 + MACHINE_EPSILON) == 1.0

sign = (x) ->
  if typeof x == 'number' # JIT compiler hint
    if x
      if x < 0 then -1 else 1
    else
      if x == x then 0 else NaN
  else
    NaN

(exports ? this).roots =
  MACHINE_EPSILON: MACHINE_EPSILON
  
  # Finds the root of f(x) near x0 given df(x) = f'(x)
  newtonsMethod: (x0, f, df) ->
    loop
      x = x0 - f(x0) / df(x0)
      return x if isNaN(x) or Math.abs(x - x0) < 1e-6 # Close enough
      x0 = x
  
  # Finds a root of f(x) between a and b
  brentsMethod: (a, b, relativeAccuracy, f, fa = f(a), fb = f(b)) ->
    c = a
    fc = fa
    d = b - a
    e = d
    relativeAccuracy += 0.5 * MACHINE_EPSILON
  
    return NaN if isNaN(fa) or isNaN(fb)
    return NaN if sign(fa) == sign(fb) # Can't find a root if the signs of fa and fb are equal
  
    i = 0
    loop
      if Math.abs(fc) < Math.abs(fb)
        a = b
        b = c
        c = a
        fa = fb
        fb = fc
        fc = fa
    
      tol = relativeAccuracy * Math.abs(b)
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
      return NaN if isNaN(fb)
    
      if (fb < 0 and fc < 0) or (fb > 0 and fc > 0)
        c = a
        fc = fa
        d = e = b - a
    
      i++
  
  # Finds the minimum of f(x) between x1 and x2. Returns x.
  # See: http://en.wikipedia.org/wiki/Golden_section_search
  goldenSectionSearch: (x1, x2, epsilon, f) ->
    k = 2 - GOLDEN_RATIO
    x3 = x2
    x2 = x1 + k * (x3 - x1)
  
    y2 = f(x2)
  
    loop
      if (x3 - x2) > (x2 - x1)
        x = x2 + k * (x3 - x2)
      else
        x = x2 - k * (x2 - x1)
    
      return (x3 + x1) / 2 if (x3 - x1) < (epsilon * (x2 + x)) # Close enough
    
      y = f(x)
      if y < y2
        if (x3 - x2) > (x2 - x1) then x1 = x2 else x3 = x2
        x2 = x
        y2 = y
      else
        if (x3 - x2) > (x2 - x1) then x3 = x else x1 = x

