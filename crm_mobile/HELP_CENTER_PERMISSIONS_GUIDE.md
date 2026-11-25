# Tickora CRM - Help Center: Permissions Setup Guide

Welcome to the **Tickora CRM Help Center**. This guide explains all permissions requested by Tickora CRM, why they are required, and provides step-by-step instructions to enable them based on your smartphone brand (**Samsung, Xiaomi/Redmi/POCO, Vivo/iQOO, Oppo/Realme, OnePlus, and Google Pixel/Stock Android**).

---

## Table of Contents
1. [Why Does Tickora CRM Need Permissions?](#1-why-does-tickora-crm-need-permissions)
2. [Complete List of Permissions Explained](#2-complete-list-of-permissions-explained)
3. [Brand-Specific Setup Instructions](#3-brand-specific-setup-instructions)
   - [Samsung (One UI)](#samsung-one-ui)
   - [Xiaomi / Redmi / POCO (MIUI / HyperOS)](#xiaomi--redmi--poco-miui--hyperos)
   - [Vivo / iQOO (Funtouch OS)](#vivo--iqoo-funtouch-os)
   - [Oppo / Realme (ColorOS / Realme UI)](#oppo--realme-coloros--realme-ui)
   - [OnePlus (OxygenOS)](#oneplus-oxygenos)
   - [Google Pixel / Motorola (Stock Android)](#google-pixel--motorola-stock-android)
4. [Critical Background Settings (Prevent App from Sleeping)](#4-critical-background-settings)
5. [Troubleshooting & Frequently Asked Questions (FAQ)](#5-troubleshooting--faq)

---

## 1. Why Does Tickora CRM Need Permissions?

Tickora CRM turns your smartphone into a smart CRM business workstation. When you receive or make client calls, Tickora CRM:
- Instantly identifies whether the caller is an existing lead or customer.
- Displays a floating caller badge so you can take notes, view lead history, or add new leads on the fly.
- Syncs call logs and auto-associates call recordings with customer profiles.
- Alerts you of pending follow-ups and lead assignments.

> 🔒 **Privacy Note**: Tickora CRM only accesses phone data required for CRM operations and client communication. Your data is encrypted and securely synced with your company’s workspace.

---

## 2. Complete List of Permissions Explained

| Permission | In-App Prompt Name | Why It Is Needed |
| :--- | :--- | :--- |
| **Phone & Call State** | `Phone` | Detects when a business call starts, connects, and ends to trigger CRM matching. |
| **Call Logs** | `Call logs` | Matches incoming/outgoing calls to existing leads, measures call duration, and logs communication history. |
| **Contacts** | `Contacts` | Cross-references numbers with your device address book so existing contacts are recognized and not duplicated. |
| **Display Over Other Apps** | `Overlay Permission` | Shows the floating caller ID card over the phone screen during incoming/outgoing calls with quick CRM actions (**View Lead**, **Quick Add Lead**). |
| **Default Caller ID & Spam** | `Caller ID / Call Screening` | Identifies client names in real-time on Android 10+ before answering the call. |
| **Music and Audio / Storage** | `All Files / Audio Permission` | Detects and uploads call recordings saved by your phone's call recorder to the lead's activity timeline. |
| **Microphone** | `Microphone` | Allows recording in-app voice notes and customer audio updates. |
| **Notifications** | `Notifications` | Delivers real-time reminders for follow-ups, new lead assignments, and background upload progress. |

---

## 3. Brand-Specific Setup Instructions

Find your smartphone brand below and follow the exact steps to enable all required permissions:

---

### Samsung (One UI)

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps**.
2. Scroll down and select **Tickora CRM**.
3. Tap **Permissions**.
4. Allow the following:
   - **Call logs** ➔ Set to *Allow*
   - **Contacts** ➔ Set to *Allow*
   - **Phone** ➔ Set to *Allow*
   - **Microphone** ➔ Set to *Allow only while using the app*
   - **Music and Audio** (or **Storage**) ➔ Set to *Allow*
   - **Notifications** ➔ Set to *Allow*

#### Step 2: Overlay Permission (Appear on top)
1. Go back to the **Tickora CRM App Info** page in Settings.
2. Tap **Appear on top** (or **Display over other apps**).
3. Toggle the switch to **ON (Allow)**.

#### Step 3: Default Caller ID & Spam App
1. Go to **Settings** > **Apps** > **Choose default apps**.
2. Tap **Caller ID & spam app**.
3. Select **Tickora CRM**.

#### Step 4: Battery Optimization (Unrestricted)
1. In **Tickora CRM App Info**, tap **Battery**.
2. Select **Unrestricted** (Prevents Samsung One UI from killing the call listener in the background).

---

### Xiaomi / Redmi / POCO (MIUI / HyperOS)

> ⚠️ **Important for Xiaomi/Poco**: MIUI/HyperOS has strict background limits and special hidden overlay permissions. Please complete all steps below for full functionality.

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps** > **Manage apps**.
2. Find and tap **Tickora CRM**.
3. Tap **App permissions**.
4. Grant: **Call logs**, **Contacts**, **Phone**, **Microphone**, **Files and media / Audio**, and **Notifications**.

#### Step 2: Other Permissions (Crucial for Floating Card)
1. Return to the **Tickora CRM App Info** page.
2. Tap **Other permissions**.
3. Enable each of the following (tap each and select **Always allow** / green tick):
   - ✅ **Display pop-up windows while running in the background**
   - ✅ **Display pop-up window**
   - ✅ **Show on Lock screen**
   - ✅ **Permanent notification**

#### Step 3: Autostart Permission
1. In the **Tickora CRM App Info** page, locate **Autostart** (or **Background autostart**).
2. Toggle **Autostart** to **ON**.
3. Tap *OK* when prompted.

#### Step 4: Battery Saver
1. In the **Tickora CRM App Info** page, scroll down and tap **Battery saver**.
2. Choose **No restrictions** (Do not restrict background activity).

---

### Vivo / iQOO (Funtouch OS)

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps** > **All apps**.
2. Select **Tickora CRM**.
3. Tap **Permissions** and allow:
   - **Phone**
   - **Call logs**
   - **Contacts**
   - **Microphone**
   - **Music and Audio** / **Storage**
   - **Notifications**

#### Step 2: Display Over Other Apps (Floating Window)
1. In **Tickora CRM App Info**, tap **Display over other apps**.
2. Turn the toggle to **ON**.

#### Step 3: Autostart & High Background Power Usage
1. Open **Settings** > **Battery** > **Background power consumption management** (or **High background power usage**).
2. Find **Tickora CRM** and select **Allow high background power usage**.
3. Open **Settings** > **Apps** > **Special app access** > **Autostart**, and turn on **Tickora CRM**.

---

### Oppo / Realme (ColorOS / Realme UI)

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps** > **App management**.
2. Select **Tickora CRM**.
3. Tap **Permissions** and set all to **Allowed**:
   - **Phone**, **Call Logs**, **Contacts**, **Microphone**, **Storage/Audio**, **Notifications**.

#### Step 2: Display Over Other Apps
1. In **Tickora CRM App Info**, tap **Display over other apps**.
2. Turn the switch **ON**.

#### Step 3: Allow Background Activity & Auto-Launch
1. In **Tickora CRM App Info**, tap **Battery usage**.
2. Enable:
   - **Allow background activity** ➔ ON
   - **Allow auto-launch** ➔ ON
   - **Allow foreground activity** ➔ ON
3. Turn off **Pause app activity if unused**.

#### Step 4: Default Caller ID App
1. Go to **Settings** > **Apps** > **Default apps**.
2. Tap **Caller ID & spam app** > Select **Tickora CRM**.

---

### OnePlus (OxygenOS)

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps** > **App management**.
2. Find and tap **Tickora CRM**.
3. Tap **Permissions** and grant:
   - **Call logs**, **Contacts**, **Phone**, **Microphone**, **Music and audio**, **Notifications**.

#### Step 2: Display Over Other Apps
1. In **Tickora CRM App Info**, scroll down to **Display over other apps**.
2. Switch toggle to **Allowed**.

#### Step 3: Battery & Auto-Launch
1. In **Tickora CRM App Info**, tap **Battery**.
2. Choose **Unrestricted** (or enable **Allow background activity** and **Allow auto-launch**).
3. Disable **Pause app activity if unused**.

#### Step 4: Set as Caller ID & Spam App
1. Go to **Settings** > **Apps** > **Default apps**.
2. Tap **Caller ID & spam app** and select **Tickora CRM**.

---

### Google Pixel / Motorola (Stock Android)

#### Step 1: Core Permissions
1. Open phone **Settings** > **Apps** > **See all apps**.
2. Tap **Tickora CRM**.
3. Tap **Permissions**:
   - Allow **Phone**, **Call logs**, **Contacts**, **Microphone**, **Music and audio** (or **Photos and videos** / **Files**), and **Notifications**.

#### Step 2: Display Over Other Apps
1. Go to **Settings** > **Apps** > **Special app access** > **Display over other apps**.
2. Tap **Tickora CRM** and turn on **Allow display over other apps**.

#### Step 3: Caller ID & Spam Role
1. Go to **Settings** > **Apps** > **Default apps**.
2. Tap **Caller ID & spam app**.
3. Choose **Tickora CRM**.

#### Step 4: Battery Optimization
1. Go back to **Tickora CRM App Info**.
2. Tap **App battery usage**.
3. Select **Unrestricted**.

---

## 4. Critical Background Settings

Many Android manufacturers automatically put background apps to "sleep" to save battery. To ensure you never miss incoming lead popups or call recording uploads:

1. **Lock Tickora CRM in Recent Apps (App Switcher)**:
   - Open your phone's Recent Apps / App Switcher screen.
   - Long-press or tap the two dots / lock icon on the **Tickora CRM** card.
   - Tap **Lock**. This prevents the system memory cleaner from closing the CRM.
2. **Turn Off "Pause App Activity If Unused"**:
   - In **Settings** > **Apps** > **Tickora CRM**, turn off **"Pause app activity if unused"** (or *Remove permissions if app is unused*).
3. **Turn on Built-in Call Recording in Your Phone's Dialer**:
   - Open your native phone **Phone / Dialer** app.
   - Tap **Settings (three dots)** > **Record calls** > Enable **Auto record calls (All numbers)**.
   - Tickora CRM will automatically detect these recordings and sync them to your leads.

---

## 5. Troubleshooting & FAQ

### Q1: The floating caller ID card is not showing during incoming or outgoing calls.
- **Solution**:
  1. Verify **Display over other apps** is enabled for Tickora CRM.
  2. On **Xiaomi/Redmi/POCO**, ensure **"Display pop-up windows while running in the background"** is explicitly set to **Allow** in *Other permissions*.
  3. Confirm that **Default Caller ID & spam app** is set to **Tickora CRM** in *Default apps*.

### Q2: Why are call recordings not uploading to leads?
- **Solution**:
  1. Confirm your native phone dialer has **Auto Call Recording** enabled.
  2. Ensure Tickora CRM has **Music and Audio** (Android 13+) or **Storage** permission granted.
  3. Ensure your phone's battery saver has **Unrestricted** background access for Tickora CRM so recordings can upload while the screen is off.

### Q3: Why does the app ask for permissions when I log in?
- **Answer**: Tickora CRM checks critical permissions right after you log in to ensure your phone is properly configured. If all permissions are already granted, you won't see any prompts. Normal app launches and background resumes do not re-prompt.

### Q4: I accidentally clicked "Don't allow". How do I re-enable?
- **Solution**: Open your phone's **Settings** > **Apps** > **Tickora CRM** > **Permissions**, and switch all permissions from *Denied* to *Allowed*.

---

*Need additional assistance? Contact the Tickora Support Team through the Help & Support section inside the app.*
