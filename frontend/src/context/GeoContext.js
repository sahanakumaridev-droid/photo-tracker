import { createContext } from 'react'

// Shared geo context — location + timestamp updated in real-time
export const GeoContext = createContext({ location: null, timestamp: null })
