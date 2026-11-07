import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    clubName: String,
    title: String,
    author: String,
    time: String,
    location: String,
    host: String,
    coverUrl: String,
    rsvpUrl: String,
    pollUrl: String,
    bookReadId: String,
    downloadSuccessMsg: String,
    downloadErrorMsg: String,
    linkSharedMsg: String,
    linkCopiedMsg: String,
    linkErrorMsg: String,
    shareTitle: String,
    shareText: String,
    labelBookClubMeetup: String,
    labelActivePoll: String,
    labelVotingInProgress: String,
    labelByAuthor: String,
    labelMeetupDetails: String,
    labelTime: String,
    labelLocation: String,
    labelHostedBy: String,
    labelScanToRsvp: String,
  };

  async download() {
    this.setLoading(true);
    try {
      const canvas = await this.drawFlyerCanvas();
      const dataUrl = canvas.toDataURL("image/png");

      const link = document.createElement("a");
      link.download = `meetup-story-flyer-${this.bookReadIdValue}.png`;
      link.href = dataUrl;
      link.click();

      this.notify(this.downloadSuccessMsgValue || "Flyer downloaded successfully!");
    } catch (error) {
      console.error("Failed to download flyer:", error);
      this.notify(this.downloadErrorMsgValue || "Failed to generate flyer.", "error");
    } finally {
      this.setLoading(false);
    }
  }

  async share() {
    this.setLoading(true);
    try {
      const canvas = await this.drawFlyerCanvas();
      const blob = await new Promise((resolve) =>
        canvas.toBlob(resolve, "image/png"),
      );

      if (!blob) {
        await this.download();
        return;
      }

      const filename = `meetup-story-flyer-${this.bookReadIdValue}.png`;
      const file = new File([blob], filename, { type: "image/png" });

      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({
          files: [file],
          title: this.shareTitleValue || "Book Club Meetup Flyer",
          text: this.shareTextValue || `Join us at ${this.clubNameValue} for a discussion on "${this.titleValue}"!`,
        });
      } else {
        await this.download();
      }
    } catch (error) {
      if (error?.name === "AbortError") return;
      console.error("Failed to share flyer:", error);
      await this.download();
    } finally {
      this.setLoading(false);
    }
  }

  async shareLink() {
    await this.shareUrl(this.rsvpUrlValue);
  }

  async sharePollLink() {
    await this.shareUrl(this.pollUrlValue || this.rsvpUrlValue);
  }

  async shareUrl(url) {
    const shareData = {
      title: this.titleValue,
      url: url,
    };

    try {
      if (navigator.share) {
        await navigator.share(shareData);
        this.notify(this.linkSharedMsgValue || "Link shared successfully!");
        return;
      }

      await navigator.clipboard.writeText(url);
      this.notify(this.linkCopiedMsgValue || "Link copied to clipboard!");
    } catch (error) {
      if (error?.name === "AbortError") return;
      console.error("Failed to share link:", error);
      this.notify(this.linkErrorMsgValue || "Failed to share link.", "error");
    }
  }

  async drawFlyerCanvas() {
    const canvas = document.createElement("canvas");
    canvas.width = 1080; // Instagram Story standard width
    canvas.height = 1920; // Instagram Story standard height
    const ctx = canvas.getContext("2d");

    // Coordinates & Padding Settings
    const padding = 80;
    const W = canvas.width;
    const H = canvas.height;

    // 1. Background (Deep spruce shelf gradient)
    const bgGradient = ctx.createLinearGradient(0, 0, 0, H);
    bgGradient.addColorStop(0, "#0a1b19");
    bgGradient.addColorStop(0.5, "#06110f");
    bgGradient.addColorStop(1, "#0f2422");
    ctx.fillStyle = bgGradient;
    ctx.fillRect(0, 0, W, H);

    // Glowing atmospheric lights (Top Spruce, Bottom Oxblood)
    const glow1 = ctx.createRadialGradient(W / 2, 250, 100, W / 2, 250, 600);
    glow1.addColorStop(0, "rgba(19, 78, 74, 0.4)"); // Spruce
    glow1.addColorStop(1, "rgba(19, 78, 74, 0)");
    ctx.fillStyle = glow1;
    ctx.fillRect(0, 0, W, H);

    const glow2 = ctx.createRadialGradient(
      W / 2,
      H - 400,
      100,
      W / 2,
      H - 400,
      600,
    );
    glow2.addColorStop(0, "rgba(140, 49, 48, 0.28)"); // Oxblood
    glow2.addColorStop(1, "rgba(140, 49, 48, 0)");
    ctx.fillStyle = glow2;
    ctx.fillRect(0, 0, W, H);

    // Helper: Rounded Rectangle path builder
    const drawRoundedRect = (x, y, w, h, r) => {
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.lineTo(x + w - r, y);
      ctx.quadraticCurveTo(x + w, y, x + w, y + r);
      ctx.lineTo(x + w, y + h - r);
      ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
      ctx.lineTo(x + r, y + h);
      ctx.quadraticCurveTo(x, y + h, x, y + h - r);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
      ctx.closePath();
    };

    // Helper: Wrap text helper (with alignment support)
    const wrapText = (
      text,
      x,
      y,
      maxWidth,
      lineHeight,
      maxLines = 10,
      align = "left",
    ) => {
      const words = text.split(/\s+/);
      let line = "";
      let currentY = y;
      let linesCount = 0;
      ctx.textAlign = align;

      for (let n = 0; n < words.length; n++) {
        const word = words[n];
        let testLine = line + word + " ";
        let metrics = ctx.measureText(testLine);
        
        if (metrics.width > maxWidth) {
          // If the word itself is wider than maxWidth, we need to split it by character
          const wordMetrics = ctx.measureText(word);
          if (wordMetrics.width > maxWidth) {
            // Write the current line if there is one
            if (line.trim().length > 0) {
              linesCount++;
              if (linesCount === maxLines) {
                ctx.fillText(line.trim() + "...", x, currentY);
                return currentY;
              }
              ctx.fillText(line.trim(), x, currentY);
              currentY += lineHeight;
              line = "";
            }
            
            // Split the long word by characters
            let chars = word.split("");
            for (let c = 0; c < chars.length; c++) {
              let testCharLine = line + chars[c];
              let charMetrics = ctx.measureText(testCharLine);
              if (charMetrics.width > maxWidth) {
                linesCount++;
                if (linesCount === maxLines) {
                  ctx.fillText(line.trim() + "...", x, currentY);
                  return currentY;
                }
                ctx.fillText(line.trim(), x, currentY);
                currentY += lineHeight;
                line = chars[c];
              } else {
                line = testCharLine;
              }
            }
            line += " "; // Add space after the character-split word
          } else {
            // Normal word wrap
            if (line.trim().length > 0) {
              linesCount++;
              if (linesCount === maxLines) {
                ctx.fillText(line.trim() + "...", x, currentY);
                return currentY;
              }
              ctx.fillText(line.trim(), x, currentY);
              currentY += lineHeight;
            }
            line = word + " ";
          }
        } else {
          line = testLine;
        }
      }

      if (line.trim().length > 0 && linesCount < maxLines) {
        ctx.fillText(line.trim(), x, currentY);
      }
      return currentY;
    };

    // Draw clean frame border around the flyer (24px padding from edge)
    ctx.strokeStyle = "rgba(255, 255, 255, 0.05)";
    ctx.lineWidth = 3;
    drawRoundedRect(24, 24, W - 48, H - 48, 36);
    ctx.stroke();

    // 2. Header Block
    ctx.textAlign = "left";
    ctx.textBaseline = "top";

    // Subtitle & Club Name (Enlarged and positioned higher)
    ctx.fillStyle = "#e6dcc3";
    ctx.font = "bold 30px sans-serif";
    ctx.fillText(this.labelBookClubMeetupValue || "BOOK CLUB MEETUP", padding, 70);

      ctx.fillStyle = "#f6f1e7";
      ctx.font = "bold 58px Georgia, serif";
    ctx.fillText(this.clubNameValue, padding, 115);

    // Separator line below header (tightened gap)
    ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(padding, 195);
    ctx.lineTo(W - padding, 195);
    ctx.stroke();

    // Reset baseline for body
    ctx.textBaseline = "top";

    // 3. Load Images concurrently
    const coverPromise = this.coverUrlValue
      ? this.loadImage(this.coverUrlValue)
      : Promise.resolve(null);
    const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(this.rsvpUrlValue)}`;
    const qrPromise = this.loadImage(qrUrl);

    const [coverImg, qrImg] = await Promise.all([coverPromise, qrPromise]);

    // 4. Draw Centered Cover Image (Maximized size: 520x780, positioned tightly at y: 235)
    const coverWidth = 520;
    const coverHeight = 780;
    const coverX = (W - coverWidth) / 2; // Center horizontally
    const coverY = 235;

    if (coverImg) {
      ctx.save();
      // Drop Shadow for Cover Image
      ctx.shadowColor = "rgba(0, 0, 0, 0.65)";
      ctx.shadowBlur = 45;
      ctx.shadowOffsetX = 0;
      ctx.shadowOffsetY = 22;

      drawRoundedRect(coverX, coverY, coverWidth, coverHeight, 32);
      ctx.fillStyle = "#04100e";
      ctx.fill();
      ctx.restore();

      // Draw the image clipped inside rounded corners
      ctx.save();
      drawRoundedRect(coverX, coverY, coverWidth, coverHeight, 32);
      ctx.clip();
      ctx.drawImage(coverImg, coverX, coverY, coverWidth, coverHeight);
      ctx.restore();

      // Clean thin border overlay
      ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
      ctx.lineWidth = 2;
      drawRoundedRect(coverX, coverY, coverWidth, coverHeight, 32);
      ctx.stroke();
    } else {
      // Placeholder icon: drawn ballot with a check (no emoji, matches the icon system)
      ctx.fillStyle = "rgba(255, 255, 255, 0.03)";
      drawRoundedRect(coverX, coverY, coverWidth, coverHeight, 32);
      ctx.fill();
      ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
      ctx.lineWidth = 1.5;
      ctx.stroke();

      const ballotW = 150;
      const ballotH = 175;
      const bx = (W - ballotW) / 2;
      const by = coverY + 195;
      ctx.strokeStyle = "#e6dcc3";
      ctx.lineWidth = 6;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      drawRoundedRect(bx, by, ballotW, ballotH, 24);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(bx + 42, by + 100);
      ctx.lineTo(bx + 70, by + 128);
      ctx.lineTo(bx + 110, by + 62);
      ctx.stroke();

      ctx.textAlign = "center";
      ctx.font = "bold 32px sans-serif";
      ctx.fillStyle = "#e6dcc3";
      ctx.fillText(this.labelActivePollValue || "ACTIVE POLL", W / 2, coverY + 410);
      ctx.font = "24px sans-serif";
      ctx.fillStyle = "#8a7c66";
      ctx.fillText(this.labelVotingInProgressValue || "Voting in Progress", W / 2, coverY + 468);
    }

    // 5. Draw Book Details (Center-aligned, positioned closely below cover y: 1045)
    let currentY = 1045;
    const bodyWidth = W - padding * 2; // 920

    // Title (Centered, maximum font size)
    ctx.fillStyle = "#f6f1e7";
    ctx.font = "bold 64px sans-serif";
    const titleLastY = wrapText(
      this.titleValue,
      W / 2,
      currentY,
      bodyWidth,
      76,
      3,
      "center",
    );
    currentY = titleLastY + 60;

    // Author (Centered, maximum font size)
    if (this.authorValue) {
      ctx.fillStyle = "#d8ccb2"; // Parchment
      ctx.font = "italic 42px sans-serif";
      ctx.textAlign = "center";
      const byText = this.labelByAuthorValue
        ? this.labelByAuthorValue.replace("%{author}", this.authorValue)
        : `by ${this.authorValue}`;
      ctx.fillText(byText, W / 2, currentY);
      currentY += 80;
    } else {
      currentY += 20;
    }

    // 6. Draw Meetup Info Box (Positioned tightly at y: 1250 with massive fonts)
    const boxY = 1250;
    const boxW = W - padding * 2; // 920
    const boxH = 340;
    const boxX = padding;

    ctx.fillStyle = "rgba(255, 255, 255, 0.03)";
    drawRoundedRect(boxX, boxY, boxW, boxH, 24);
    ctx.fill();

    // Card border
    ctx.strokeStyle = "rgba(255, 255, 255, 0.06)";
    ctx.lineWidth = 2;
    drawRoundedRect(boxX, boxY, boxW, boxH, 24);
    ctx.stroke();

    // Box Title
    ctx.textAlign = "left";
    ctx.fillStyle = "#e6dcc3";
    ctx.font = "bold 26px sans-serif";
    ctx.fillText(this.labelMeetupDetailsValue || "MEETUP DETAILS", boxX + 40, boxY + 36);

    // Box Rows (Maximum font size: 42px, highly readable)
    const timeLabel = this.labelTimeValue || "Time";
    const locationLabel = this.labelLocationValue || "Location";
    const hostedByText = this.labelHostedByValue
      ? this.labelHostedByValue.replace("%{host}", this.hostValue)
      : `Host:  ${this.hostValue}`;

    // Drawn row icons (clock, pin, person) in place of emoji glyphs
    const drawRowIcon = (kind, x, cy, color = "#f6f1e7") => {
      ctx.save();
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = 3.5;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      const r = 17;
      if (kind === "clock") {
        ctx.beginPath();
        ctx.arc(x + r, cy, r, 0, Math.PI * 2);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(x + r, cy - 9);
        ctx.lineTo(x + r, cy);
        ctx.lineTo(x + r + 8, cy + 5);
        ctx.stroke();
      } else if (kind === "pin") {
        ctx.beginPath();
        ctx.arc(x + r, cy - 7, 10, 0, Math.PI * 2);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(x + r - 6, cy - 1);
        ctx.lineTo(x + r, cy + 14);
        ctx.lineTo(x + r + 6, cy - 1);
        ctx.closePath();
        ctx.fill();
      } else if (kind === "person") {
        ctx.beginPath();
        ctx.arc(x + r, cy - 10, 8, 0, Math.PI * 2);
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(x + r, cy + 16, 15, Math.PI, 2 * Math.PI);
        ctx.stroke();
      }
      ctx.restore();
    };

    // Long meetup details stay inside the info box: shrink the row font until
    // the text fits, never below a readable floor.
    const maxDetailWidth = W - (boxX + 94) - (padding + 40);
    const fitDetail = (type, base, text) => {
      let size = base;
      ctx.font = `${type} ${size}px sans-serif`;
      while (ctx.measureText(text).width > maxDetailWidth && size > 22) {
        size -= 2;
        ctx.font = `${type} ${size}px sans-serif`;
      }
      return size;
    };

    drawRowIcon("clock", boxX + 40, boxY + 119);
    fitDetail("bold", 42, `${timeLabel}:  ${this.timeValue}`);
    ctx.fillStyle = "#f6f1e7";
    ctx.fillText(`${timeLabel}:  ${this.timeValue}`, boxX + 94, boxY + 100);
    drawRowIcon("pin", boxX + 40, boxY + 194);
    fitDetail("bold", 42, `${locationLabel}:  ${this.locationValue}`);
    ctx.fillText(`${locationLabel}:  ${this.locationValue}`, boxX + 94, boxY + 175);

    drawRowIcon("person", boxX + 40, boxY + 267, "#cfc2a6");
    const hostSize = fitDetail("", 40, hostedByText);
    ctx.fillStyle = "#cfc2a6";
    ctx.font = `${hostSize}px sans-serif`;
    ctx.fillText(hostedByText, boxX + 94, boxY + 250);

    // 7. Footer Block (Positioned higher, y: 1650)
    const footerY = 1650;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(padding, footerY);
    ctx.lineTo(W - padding, footerY);
    ctx.stroke();

    // Left Footer Text (Scaled up)
    ctx.fillStyle = "#e6dcc3";
    ctx.font = "bold 32px sans-serif";
    ctx.fillText(this.labelScanToRsvpValue || "SCAN TO RSVP", padding, footerY + 35);

    ctx.fillStyle = "#a3957b";
    ctx.font = "26px sans-serif";
    wrapText(
      this.rsvpUrlValue,
      padding,
      footerY + 80,
      W - padding - 220,
      32,
      2,
      "left",
    );

    // Right Footer QR Code (160x160)
    if (qrImg) {
      ctx.save();
      const qrSize = 160;
      const qrX = W - padding - qrSize;
      const qrY = footerY + 20;
      drawRoundedRect(qrX, qrY, qrSize, qrSize, 14);
      ctx.fillStyle = "#ffffff";
      ctx.fill();
      ctx.clip();
      ctx.drawImage(qrImg, qrX + 6, qrY + 6, qrSize - 12, qrSize - 12);
      ctx.restore();
    }

    return canvas;
  }

  loadImage(src, timeoutMs = 10000) {
    return new Promise((resolve) => {
      const img = new Image();
      let settled = false;
      
      const finish = (value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        resolve(value);
      };

      const timeout = setTimeout(() => {
        console.warn(`Timed out loading image: ${src}`);
        finish(null);
      }, timeoutMs);

      img.crossOrigin = "anonymous";
      img.onload = () => finish(img);
      img.onerror = (e) => {
        console.warn(`Failed to load image: ${src}`, e);
        finish(null);
      };
      img.src = src;
    });
  }

  setLoading(isLoading) {
    const buttons = this.element.querySelectorAll("button");
    buttons.forEach((btn) => {
      if (isLoading) {
        btn.setAttribute("disabled", "true");
        btn.style.opacity = "0.7";
      } else {
        btn.removeAttribute("disabled");
        btn.style.opacity = "1";
      }
    });
  }

  notify(text, type = "success") {
    if (window.toast) {
      window.toast(text, { type });
    } else {
      alert(text);
    }
  }
}
