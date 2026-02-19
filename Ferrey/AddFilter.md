# AddFilter.md  
_Ferrey_  
_Created by Junaid on 12/09/2025_

---

## 🖌️ How to Add a New Filter to Ferrey App

Follow these steps to add a new filter to the app:

---

### 1️⃣ Add the Filter Case
Open `FilterType.swift` and make changes as written.

---

### 6️⃣ Test in the App
After adding your filter:

- ✅ The filter appears in the filter bar.  
- ✅ The icon and title display correctly.  
- ✅ The LUT file loads and produces the expected color result.  
- ✅ Lock icon appears if it is marked as Pro and Pro mode is disabled.  

---

## 💡 Tips

- **Keep naming consistent:** enum case, title string,  icon asset, and LUT file name must match.
- **Use short and clear titles** so they fit nicely in the UI.
- **Add sample previews** to improve UX.
- **Test performance** when adding multiple filters — Core Image filters are GPU-intensive.

---

✅ Once complete, your new filter is fully integrated and will be saved/loaded automatically like all existing filters.
