# 🎨 Design Guide - Modern UI/UX 2026

## Navigation Bar Design

### Visual Structure
```
┌─────────────────────────────────────────────────────┐
│  [Home]  [Profiles]  [Upload]  [Log]  [Settings]   │
│   🏠      📁         📷        📋      ⚙️            │
│  Active: Highlighted with gradient background      │
│  Inactive: Gray icons                               │
└─────────────────────────────────────────────────────┘
```

### Features
- **Glassmorphism**: Frosted glass effect with backdrop blur
- **Rounded Top**: 24px border radius
- **Shadow**: Subtle elevation shadow
- **Animation**: Scale on tap (300ms)
- **Active State**: Gradient background + border

### Color Scheme
```
Active Item:
  - Background: Primary color (15% opacity)
  - Border: Primary color (30% opacity)
  - Icon: Primary color
  - Text: Primary color (bold)

Inactive Item:
  - Background: Transparent
  - Icon: Gray
  - Text: Gray (regular weight)
```

---

## Home Screen Layout

### Header Section
```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  Welcome Home                                       │
│  Track your location-based photos                   │
│                                                     │
│  [Gradient Background: Primary → Primary (70%)]    │
└─────────────────────────────────────────────────────┘
```

### Statistics Section
```
┌─────────────────────────────────────────────────────┐
│ Your Statistics                                     │
│                                                     │
│  ┌──────────────────┐  ┌──────────────────┐        │
│  │ 📷 Total Photos  │  │ 📁 Profiles      │        │
│  │ 42               │  │ 5                │        │
│  └──────────────────┘  └──────────────────┘        │
│                                                     │
│  ┌──────────────────┐  ┌──────────────────┐        │
│  │ 📅 This Month    │  │ 📈 Avg/Profile   │        │
│  │ 12               │  │ 8                │        │
│  └──────────────────┘  └──────────────────┘        │
│                                                     │
│  [Each card has gradient background + border]      │
└─────────────────────────────────────────────────────┘
```

### AI Insights Card
```
┌─────────────────────────────────────────────────────┐
│ ✨ AI Insights                                      │
│                                                     │
│ 🚀 You're very productive! Keep up the great work! │
│                                                     │
│ [Glassmorphic background with icon]                │
└─────────────────────────────────────────────────────┘
```

### Filter Section
```
┌─────────────────────────────────────────────────────┐
│ Filter by Profile                                   │
│                                                     │
│ [All] [Profile 1] [Profile 2] [Profile 3] →       │
│                                                     │
│ [Horizontal scrollable chips]                       │
└─────────────────────────────────────────────────────┘
```

### View Mode Selector
```
┌─────────────────────────────────────────────────────┐
│ ┌──────────────────┬──────────────────┐            │
│ │ 📊 Grid          │ 📋 List          │            │
│ │ (Active)         │                  │            │
│ └──────────────────┴──────────────────┘            │
│                                                     │
│ [Segmented button with smooth transitions]         │
└─────────────────────────────────────────────────────┘
```

### Photo Grid View
```
┌─────────────────────────────────────────────────────┐
│ ┌──────────────┐  ┌──────────────┐                 │
│ │              │  │              │                 │
│ │   [Image]    │  │   [Image]    │                 │
│ │              │  │              │                 │
│ │ Profile Name │  │ Profile Name │                 │
│ │ [RUSH]       │  │ [STANDARD]   │                 │
│ └──────────────┘  └──────────────┘                 │
│                                                     │
│ ┌──────────────┐  ┌──────────────┐                 │
│ │              │  │              │                 │
│ │   [Image]    │  │   [Image]    │                 │
│ │              │  │              │                 │
│ │ Profile Name │  │ Profile Name │                 │
│ │ [AIRPORT]    │  │ [STANDARD]   │                 │
│ └──────────────┘  └──────────────┘                 │
│                                                     │
│ [2-column grid with gradient overlays]             │
└─────────────────────────────────────────────────────┘
```

### Photo List View
```
┌─────────────────────────────────────────────────────┐
│ ┌──────────────────────────────────────────────┐   │
│ │ [Thumb] Profile Name          [RUSH]         │   │
│ │         2024-05-12                           │   │
│ │         Zip: 10001                           │   │
│ └──────────────────────────────────────────────┘   │
│                                                     │
│ ┌──────────────────────────────────────────────┐   │
│ │ [Thumb] Profile Name          [STANDARD]     │   │
│ │         2024-05-11                           │   │
│ │         Zip: 10002                           │   │
│ └──────────────────────────────────────────────┘   │
│                                                     │
│ ┌──────────────────────────────────────────────┐   │
│ │ [Thumb] Profile Name          [AIRPORT]      │   │
│ │         2024-05-10                           │   │
│ │         Zip: 10003                           │   │
│ └──────────────────────────────────────────────┘   │
│                                                     │
│ [List items with thumbnails and details]          │
└─────────────────────────────────────────────────────┘
```

---

## Color Palette

### Primary Colors
```
Primary:        #6366f1 (Indigo)
Secondary:      #8b5cf6 (Purple)
Success:        #10b981 (Green)
Warning:        #F59E0B (Amber)
Error:          #ef4444 (Red)
Info:           #0ea5e9 (Cyan)
```

### Service Type Colors
```
Rush:           #ef4444 (Red)
Standard:       #10b981 (Green)
Airport:        #0ea5e9 (Cyan)
```

### Stat Card Colors
```
Total Photos:   #0ea5e9 (Blue)
Profiles:       #10b981 (Green)
This Month:     #F59E0B (Orange)
Avg/Profile:    #8b5cf6 (Purple)
```

### Background Colors
```
Light Mode:
  Background:   #ffffff
  Surface:      #F8FAFC
  Border:       #e2e8f0
  Text:         #0f172a
  Text Secondary: #64748b

Dark Mode:
  Background:   #1a1830
  Surface:      #2d2640
  Border:       #3d3650
  Text:         #f1f5f9
  Text Secondary: #cbd5e1
```

---

## Typography

### Font Sizes
```
Display Large:  32px (Bold)
Display Medium: 28px (Bold)
Headline Small: 20px (Semi-bold)
Title Large:    18px (Semi-bold)
Body Large:     16px (Medium)
Body Medium:    14px (Regular)
Body Small:     12px (Regular)
```

### Font Weights
```
Bold:           700
Semi-bold:      600
Medium:         500
Regular:        400
```

---

## Spacing System

### Base Unit: 4px
```
xs:  4px
sm:  8px
md:  12px
lg:  16px
xl:  24px
2xl: 32px
3xl: 48px
```

### Common Spacing
```
Card Padding:       16px
Section Padding:    16px
Element Gap:        12px
Section Gap:        24px
Bottom Padding:     32px (for FAB clearance)
```

---

## Border Radius

```
Small:          4px   (inputs, small elements)
Medium:         8px   (cards, buttons)
Large:          12px  (large cards)
Extra Large:    16px  (photo cards)
Full:           24px  (navigation bar top)
```

---

## Shadows

### Elevation System
```
Subtle:     0 2px 4px rgba(0,0,0,0.1)
Medium:     0 4px 8px rgba(0,0,0,0.15)
Large:      0 8px 16px rgba(0,0,0,0.2)
Extra:      0 12px 24px rgba(0,0,0,0.25)

Navigation Bar: 0 -5px 20px rgba(0,0,0,0.1)
```

---

## Animation Timings

### Standard Durations
```
Fast:       200ms
Normal:     300ms
Slow:       400ms
Extra Slow: 600ms
```

### Common Animations
```
Fade In:        600ms
Slide In:       400ms
Scale:          300ms
Stagger Delay:  100ms between items
```

---

## Responsive Breakpoints

```
Mobile:     < 600px
Tablet:     600px - 1200px
Desktop:    > 1200px

Current Focus: Mobile (Flutter mobile app)
```

---

## Glassmorphism Effect

### Navigation Bar
```
Backdrop Filter:  Blur (10px)
Background:       Color with 85% opacity
Border:           Subtle 1px border with 50% opacity
Shadow:           Elevation shadow
```

### Cards
```
Background:       Gradient with transparency
Border:           1.5px with 20% opacity
Overlay:          Gradient for depth
```

---

## Micro-interactions

### Button Tap
```
Scale:      1.0 → 0.95 → 1.0
Duration:   300ms
Feedback:   Visual scale change
```

### Navigation Item Active
```
Background:     Fade in (300ms)
Border:         Fade in (300ms)
Icon Color:     Change to primary
Text Weight:    Regular → Bold
```

### Photo Card Hover
```
Scale:          1.0 → 1.02
Shadow:         Increase elevation
Duration:       200ms
```

---

## Accessibility

### Touch Targets
```
Minimum:    48px × 48px
Recommended: 56px × 56px
Navigation: 64px height
```

### Color Contrast
```
Text on Background:     4.5:1 (WCAG AA)
Text on Colored:        3:1 minimum
Icons:                  3:1 minimum
```

### Typography
```
Minimum Font Size:      12px
Line Height:            1.5x font size
Letter Spacing:         0.5px for body text
```

---

## Dark Mode Support

### Automatic Adaptation
```
Light Mode:
  - White backgrounds
  - Dark text
  - Bright accents

Dark Mode:
  - Dark backgrounds (#1a1830)
  - Light text
  - Adjusted opacity
```

### Color Adjustments
```
Backgrounds:    Automatically inverted
Text:           Automatically inverted
Borders:        Adjusted for contrast
Shadows:        Reduced opacity
```

---

## Performance Considerations

### Animations
- 60fps target
- GPU-accelerated transforms
- Efficient repaints
- Lazy loading for images

### Rendering
- Efficient widget tree
- Minimal rebuilds
- Cached images
- Optimized layouts

---

## USA Market Optimization

### Design Principles
1. **Professional**: Clean, corporate aesthetic
2. **Trustworthy**: Clear information hierarchy
3. **Efficient**: Quick access to features
4. **Accessible**: WCAG compliant
5. **Modern**: 2026-ready design patterns

### Cultural Considerations
- Clear English labels
- Standard US date formats
- Familiar icons and patterns
- Professional color scheme

---

**Design System Version**: 1.0
**Last Updated**: May 2026
**Status**: ✅ Production Ready
