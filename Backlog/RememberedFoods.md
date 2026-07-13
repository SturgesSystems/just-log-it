# P2 — Remembered foods

- [x] Store normalized input/search signatures mapped to previously selected FDC IDs (`RememberedFoodCatalog` + `UserDefaultsRememberedFoodStore`)
- [x] Give prior selections a bounded deterministic ranking boost (`FoodSearchResultRanker.rememberedSelectionBoost`)
- [x] Always require confirmation (boost only; never auto-select)
- [x] Clear remembered selections in Settings
- [ ] Show a browsable list of remembered selections in Settings / sidebar
- [ ] Measure repeat-flow time and incorrect-alias recovery
