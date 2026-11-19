# All-in-One Utility Launcher (Modern Desktop GUI)

โปรแกรม Launcher สำหรับติดตั้งและปรับแต่ง Windows พัฒนาด้วย **HTML5 / Tailwind CSS / Vanilla JS** และรันเป็น **Desktop GUI หน้าต่างขอบมน ไร้ขอบเดิม และพื้นหลังโปร่งใส** ผ่าน PowerShell + Microsoft Edge WebView2

---

## วิธีใช้งานด่วน (One-Liner Execution)

เปิด **PowerShell** (แนะนำคลิกขวา Run as Administrator) แล้วคัดลอกคำสั่งนี้ไปวางได้ทันที:

```powershell
irm https://raw.githubusercontent.com/phwyverysad/powershell/main/launcher.ps1 | iex
```

---

## คุณสมบัติเด่น (Features)

- **Floating Frameless Rounded Window**: หน้าต่างลอยขอบมน (`rounded-24px`) ไม่มีกรอบหน้าต่างเดิมของระบบปฏิบัติการ ขอบมุมนอกหน้าต่างโปร่งใส 100%
- **Window Controls & Drag Support**:
  - ลากหน้าต่างได้จาก Header โดยตรง
  - ปุ่มย่อหน้าต่าง (Minimize), ขยาย/คืนขนาด (Maximize/Restore), ปิดโปรแกรม (Close)
- **Minimalist Falling Matrix Rain Canvas**: เอฟเฟกต์ตัวอักษร Matrix สไตล์มินิมอลไหลแบบเรียลไทม์ พร้อมการโต้ตอบตามตำแหน่งเมาส์
- **Interactive Theming & Localization**:
  - สลับโหมด Dark / Light พร้อมอนิเมชันคลื่นน้ำ
  - รองรับ 2 ภาษา (ไทย TH / อังกฤษ EN)
- **Real Execution & Live Log Streaming**:
  - เมื่อกดติดตั้งโปรแกรม ระบบจะเรียกคำสั่งจริง (`winget`, คำสั่งระบบ) ผ่าน Background Process ของ PowerShell
  - สตรีม Log บรรทัดต่อบรรทัดแบบเรียลไทม์ขึ้นหน้าต่าง Install Log Modal โดยไม่ทำให้ GUI ค้าง
- **Fast Search Autocomplete**: ค้นหาโปรแกรมแบบทันทีพร้อมคีย์ลัดลูกศรขึ้น-ลง และกด Enter เพื่อเลือก
