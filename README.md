# 🎶 **20Hz Tone Player - Keep Your Polk Audio Soundbar Awake!**  

## 🔊 **What is this?**  

Are you tired of your **Polk Audio soundbar randomly turning off** or **cutting off the start of sentences** because it thinks silence means ‘nap time’? 😤  

😏 **Well, 20Hz Tone Player is here to fix that nonsense!**  

This **Electron app** runs in the background and plays an **inaudible 20Hz tone** to keep your soundbar awake.  
- 🔊 **Your ears won’t hear it, but your soundbar will stay awake.**  
- 🎮 **No more sound dropouts or missing words in movies!**  
- 🔒 **No ads, no tracking—just pure soundbar life support.** 🎩✨  

---

## 🚀 **Features**  

🏆 **Sits quietly in your menu bar** – No clutter, just works.  
🔊 **Plays a 20Hz tone** that your soundbar hears, but you don’t.  
🌌 **Auto volume fade-in** – Starts at **0%** and rises slowly to **25%**.  
🔄 **Auto shut-off after 30 minutes of inactivity.**  
🎥 **Won’t stop if you’re watching Netflix or YouTube!**  
🔐 **Offline & Private** – No network access needed, no spying.  

---

## 👅 **How to Install**  

### 🏆 **Recommended Way (Download the .dmg)**  
1️⃣ Go to the **[Releases](https://github.com/david4price/volume20Hz/releases)** page.  
2️⃣ Download the latest **.dmg** file.  
3️⃣ Open it and **drag the app into your Applications folder**.  
4️⃣ **Launch it** and forget about your soundbar ever shutting off again. 🎶  

---

## 🛠️ **How to Build the App Yourself**  

If you’re **paranoid** or just love **DIY**, here’s how to build it from source:  

### 💡 **1️⃣ Install Dependencies**  
First, install **[Node.js](https://nodejs.org/)** if you haven’t already.  
Then, in the project folder, run:  

```sh
npm install
```

### 💡 **2️⃣ Build the macOS App**  
Run the following command:  

```sh
electron-builder build --mac
```

This will generate a **.dmg installer** and **.app** file inside the `dist/` folder.  

### 💡 **3️⃣ Install & Run the App**  
- 📂 **Open `dist/20HzTonePlayer.dmg` and drag the app to Applications.**  
- 🔍 **Launch it from Finder or Spotlight.**  

---

## 🎧 **How to Use**  

🎶 **Click the tray icon** → Hit **Play** → Your soundbar stays awake.  
🚫 **Press Stop** if you want to pause the tone.  
🕒 **Auto-shuts off after 30 minutes of inactivity** (except when watching videos).  
🛋️ **Quit anytime from the tray menu.**  

---

## ⚠️ **Known Issues (aka Features)**  

🐕 **Might make your dog tilt its head** – Some dogs hear 20Hz, mine just ignores it. 🤷‍♂️  
🔇 **Doesn’t work on Windows** – Polk Audio bars don’t need this trick on Windows.  
🍵 **Still doesn’t make your Polk Audio soundbar fetch coffee.**  

---

## 🤔 **Why This Exists?**  

Polk Audio soundbars have a mind of their own—they love to:  
- **Randomly turn off** when they detect “inactivity.”  
- **Cut off the first word of a sentence** when sound resumes after near silence.  

This **20Hz trick** keeps the bar **awake and ready**, preventing both issues **without any annoying noise!**  

### 🎩 **Why 20Hz?**  

Most Polk soundbars treat **any active audio signal as “in use”**,  
but **20Hz is too low for humans to hear**. So while your soundbar **thinks it’s busy**,  
**your ears hear nothing, and your movies sound perfect!** 🔥✨  

---

## 💡 **Support & Contributions**  

I made this **for myself**, but figured others might find it useful.  
If you want to contribute, **open an issue or fork the repo!**  

Enjoy **uninterrupted soundbar experience**! 🔥🎶  

---

### 🛠️ Windows & Linux Build Commands
🚨 Haven't tested on Windows & Linux but it should technically work... 🚨
#### **Windows**

Run the following command on Windows to build the `.exe` installer:
```sh
electron-builder build --win
```
✅ For a **portable version** (no installation required):
```sh
electron-builder build --win --portable
```

#### **Linux**
Run this on **Linux**, or cross-compile from macOS:
```sh
electron-builder build --linux
```
✅ For a specific format:
```sh
electron-builder build --linux appimage  # .AppImage format
```
```sh
electron-builder build --linux deb  # .deb package
```

If anyone needs a **Windows or Linux version**, let me know, and I'll ensure it's tested! 💪🌟

