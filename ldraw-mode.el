;;; ldraw-mode.el --- simple major mode for editing LDraw DAT-files


;; Copyright 1999, 2000, 2001, 2002 Fredrik Glöckner

;; Author: Fredrik Glöckner <fredrigl@math.uio.no>
;; Keywords: util

;; Last revision: 22-OCT-2002


;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.


;;; INSTALL:

;; Put the file somewhere in Emacs' load-path, byte compile it, and load
;; it from your .emacs with
;;
;;     (load "ldraw-mode")
;;
;; If you are unsure about the contents of Emacs' load-path, you can
;; examine it by pressing `C-h v load-path RET'.
;;
;; You don't really need to byte compile the source file, but doing so
;; will improve the execution speed.  You can byte compile an Emacs
;; Lisp file by pressing `M-x byte-compile-file RET' and then state
;; the file name.  `M-x' is normally bound to the key combination
;; `ALT+x', but you can also press `ESC' followed by `x'.
;;
;;
;; You may want to read through the top section of the code, to see
;; which variables you can alter.  If you have the LDraw base dir
;; somewhere else than where I have it, say, you may want to put
;; something like this in your .emacs file:
;;
;;     (setq ldraw-base-dir "/where/I/have/ldraw")
;;
;; Note that LDraw-mode doesn't actually use any of the programs
;; included in LDraw.  It needs to know where the LDraw root is to be
;; able to inline parts and to search in the PARTS.LST file.  If you
;; have no need for these things, you don't need to tell LDraw-mode
;; where the LDraw root is.
;;
;; If there are other things you want to change in the LDraw-mode
;; configuration, do the changes in your .emacs file, not in this
;; source file.  For example, to preserve three decimal places rather
;; than two by default, put this in your .emacs file:
;;
;;     (setq ldraw-number-of-decimal-places 3)
;;
;; Restart Emacs to make sure the changes are applied.


;;; TODO: What I plan to include in the future

;; - LEdit emulation mode; handle part rotation and more (in progress,
;;   hit "C-c C-e")
;; - Inlining models (finished!  Hit "C-c C-i" to inline a part.)
;; - Launching LDLITE and more
;; - Better font lock regexps to nag the user about wrongly specified
;;   lines and support LDLITE style imperatives
;; - Pull down menus (in progress)
;; - Searching for a specific part (in progress, hit "C-c C-s")
;; - Improve the parser.  Right now, it barfs when encountering wrongly
;;   formatted lines.


;;; Code:

;; This setup assumes that you've got the LDraw directory located at
;; C:\LDRAW if you are running Windows, or /usr/local/share/ldraw for
;; GNU/Linux.
;;
;; Alternatively, if the environment variable LDRAWDIR is set, we
;; assume this is the correct path.
(defvar ldraw-base-dir (or (getenv "LDRAWDIR")
                           (if (string= system-type "windows-nt")
                               "C:/ldraw"
                             "/usr/local/share/ldraw"))
  "Base LDraw dir.

If you're on a MSDOS system, you may need to put something like
    (setq ldraw-base-dir \"C:/ldraw\") 
in your .emacs file.  Note the forward slashes in the path.")

(defvar ldraw-viewer-path (if (string= system-type "windows-nt")
                              "C:/ldraw/ldglite/ldglite"
                            "/usr/local/share/ldglite")
  "Base Ldraw file viewer path.

If you're on a MSDOS system, you may need to put something like
    (setq ldraw-viewer-path \"C:/projects/ldglite/ldglite.exe\")
in your .emacs file.  Note the forward slashes in the path.")

(defvar ldraw-viewer-args "-v3 -p -l3"
  "Arguments to pass to the viewer program.")

(defvar ldraw-parts-lst-file-name "parts.lst"
  "The name of the parts.lst file.

The name is relative to the `ldraw-base-dir' directory.")

(defvar ldraw-path '("p" "parts" "parts/s" "parts/48" "models")
  "Where the inliner shall look for files to inline.

Note that the current directory is searched first, complying with the
LDraw standard.")

(defvar ldraw-turn-centre '(0 0 0)
  "Centre point for turning parts.")

(defvar ldraw-inline-indent "  " 
  "Indentation for each layer of inlineing in a model.")

(defvar ldraw-cut-edge t
  "Make an edge when cutting triangles or quadilaterals.")

(defvar ldraw-number-of-decimal-places 2
  "Number of decimals to preserve.")

(defvar ldraw-bezier-draw-control-lines nil
  "Draw type-2 lines describing the control lines.  Optionally include
two type-2 lines when doing Bézier curves.  The lines illustrate the
distance from the starting point to the first control point, and from
the end point to the second control point.")

(defvar ldraw-bezier-integration-points-per-segment 12
  "Number of integration points per Bézier curve segment.
The higher the number, the more precise the curve will be, but the
calculations will be more computer intensitive.")

(defvar ldraw-bezier-integration-epsilon 0.07 
  "Highest acceptable error.")

(defvar ldraw-bezier-integration-max-iterations 100
  "Maximium number of iterations.")

(defvar ldraw-bezier-rotate-vector (list 0 1 0)
  "The first axis in the rotated coordinate system should be
perpendicular to this vector.  Try to alter this vector if you
experience weird twisting of the curve.  In general, avoid a vector
which is close in direction to the curve at any point to avoid this
twisting.")

(defvar ldraw-parts-images-web-base "http://img.lugnet.com/ld/")

(defvar ldraw-colour-names 
  '("Black"
    "Blue"
    "Green"
    "Dark-cyan"
    "Red"
    "Magenta"
    "Brown"
    "Light-gray"
    "Dark-gray"
    "Light-blue"
    "Light-green"
    "Cyan"
    "Light-red"
    "Pink"
    "Yellow"
    "White"))

;; The table below originates from Steve Bliss.
(defvar ldraw-edge-colour-table
  '(8 9 10 11 12 13 0 8 0 1 2 3 4 5 8 8)
  "Table of edge colours to apply to inlined elements with colour 24.")

(defvar ldraw-ring-primitives-available '(1 2 3 4 7 10)
  "List of available ring primitives.")

;; Recognize ".dat" and ".mpd" files as LDraw DAT files.
(if (assoc "\\.dat\\'" auto-mode-alist) nil
  (setq auto-mode-alist
	(append
	 '(("\\.dat\\'"    . ldraw-mode))
	 '(("\\.DAT\\'"    . ldraw-mode))
	 auto-mode-alist)))
(if (assoc "\\.mpd\\'" auto-mode-alist) nil
  (setq auto-mode-alist
	(append
	 '(("\\.mpd\\'"    . ldraw-mode))
	 '(("\\.MPD\\'"    . ldraw-mode))
	 auto-mode-alist)))
(if (assoc "\\.ldr\\'" auto-mode-alist) nil
  (setq auto-mode-alist
	(append
	 '(("\\.ldr\\'"    . ldraw-mode))
	 '(("\\.LDR\\'"    . ldraw-mode))
	 auto-mode-alist)))

;; We use the DOS-style coding system to achieve the correct EOL type, LF+CR.
;; This only applies to Emacs 20.x
(if (> emacs-major-version 19)
    (if (assoc "\\.dat\\'" file-coding-system-alist) nil
      (setq file-coding-system-alist
            (append
             '(("\\.dat\\'"    raw-text-dos . raw-text-dos))
             '(("\\.DAT\\'"    raw-text-dos . raw-text-dos))
             file-coding-system-alist))))
(if (> emacs-major-version 19)
    (if (assoc "\\.mpd\\'" file-coding-system-alist) nil
      (setq file-coding-system-alist
            (append
             '(("\\.mpd\\'"    raw-text-dos . raw-text-dos))
             '(("\\.MPD\\'"    raw-text-dos . raw-text-dos))
             file-coding-system-alist))))
(if (> emacs-major-version 19)
    (if (assoc "\\.ldr\\'" file-coding-system-alist) nil
      (setq file-coding-system-alist
            (append
             '(("\\.ldr\\'"    raw-text-dos . raw-text-dos))
             '(("\\.LDR\\'"    raw-text-dos . raw-text-dos))
             file-coding-system-alist))))

(defvar ldraw-mode-syntax-table nil
  "Syntax table used while in LDraw mode.")

(defvar ldraw-mode-map ()
  "Keymap used in LDraw-mode buffers.")

(defvar ldraw-ledit-mode-map ()
  "Keymap used in LEdit emulator.")

(defvar ldraw-search-mode-map ()
  "Keymap used in LDraw search buffer.")

(defvar ldraw-mode-hook ()
  "Hooks to run when starting LDraw-mode.")

(if ldraw-mode-map
    ()
  (setq ldraw-mode-map (make-sparse-keymap))
  (define-key ldraw-mode-map "\C-c\C-l" 'ldraw-ledit-mode)
  (define-key ldraw-mode-map "\C-c\C-q" 'ldraw-clean-line)
  (define-key ldraw-mode-map "\C-c\C-i" 'ldraw-inline-line)
  (define-key ldraw-mode-map "\C-c\C-t" 'ldraw-turn-line)
  (define-key ldraw-mode-map "\C-c\C-m" 'ldraw-move-line)
  (define-key ldraw-mode-map "\C-c\C-v" 'ldraw-bfc-reverse)
  ;; I suppose nobody needs this function...
  ;;  (define-key ldraw-mode-map "\C-c\C-r" 'ldraw-rotate-at-random-round-centre-of-part)
  (define-key ldraw-mode-map "\C-c\C-x" 'ldraw-launch-viewer)
  (define-key ldraw-mode-map "\C-c\C-p" 'ldraw-fetch-part-image-from-web)
  (define-key ldraw-mode-map "\C-c\C-s" 'ldraw-enter-search-buffer)
  (define-key ldraw-mode-map "\C-c\C-y" 'ldraw-insert-part-line)
  (define-key ldraw-mode-map "\C-c\C-b" 'ldraw-insert-bezier-curve)
  (define-key ldraw-mode-map "\C-c\C-r" 'ldraw-insert-ring-primitive)
  (define-key ldraw-mode-map "\C-c\C-f" 'ldraw-fill-in-surface)
  (define-key ldraw-mode-map "\C-c;" 'ldraw-comment-region)
  (define-key ldraw-mode-map "\C-c:" 'ldraw-un-comment-region)
  (define-key ldraw-mode-map "\C-c\C-c" 'ldraw-cut-line)
  (define-key ldraw-mode-map "\C-c\C-e" 'ldraw-check-for-identical-vertices)
  (define-key ldraw-mode-map [menu-bar] (make-sparse-keymap))
  (define-key ldraw-mode-map [menu-bar ldraw]
    (cons "LDraw" (make-sparse-keymap "LDraw")))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-clean-line]
    '("Clean Line" . ldraw-clean-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-launch-viewer]
    '("Launch Viewer" . ldraw-launch-viewer))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-inline-line]
    '("Inline Line" . ldraw-inline-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-ledit-mode]
    '("LEdit Mode" . ldraw-ledit-mode))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-enter-search-buffer]
    '("Enter Search Buffer" . ldraw-enter-search-buffer))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-turn-line]
    '("Rotate Object" . ldraw-turn-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-move-line]
    '("Translate Object" . ldraw-move-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-bfc-reverse]
    '("Reverse triangle/quad (BFC)" . ldraw-bfc-reverse))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-insert-bezier-curve]
    '("Insert Bézier Curve" . ldraw-insert-bezier-curve))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-insert-part-line]
    '("Insert Part" . ldraw-insert-part-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-fetch-part-image-from-web]
    '("Fetch Part Image from Web" . ldraw-fetch-part-image-from-web))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-comment-region]
    '("Comment Region" . ldraw-comment-region))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-un-comment-region]
    '("Uncomment Region" . ldraw-un-comment-region))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-insert-ring-primitive]
    '("Fill in Surface between two Curves" . ldraw-fill-in-surface))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-fill-in-surface]
    '("Insert Ring Primitive" . ldraw-insert-ring-primitive))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-cut-line]
    '("Cut below X-Z-plane" . ldraw-cut-line))
  (define-key ldraw-mode-map [menu-bar ldraw ldraw-check-for-identical-vertices]
    '("Check for Identical Vertices" . ldraw-check-for-identical-vertices))
  )

(if ldraw-ledit-mode-map
    ()
  (setq ldraw-ledit-mode-map (cons 'keymap ldraw-mode-map))
  (define-key ldraw-ledit-mode-map [prior] '(lambda ()
                                              (interactive)
                                              (forward-line -1)))
  (define-key ldraw-ledit-mode-map [next] 'forward-line)
  (define-key ldraw-ledit-mode-map "w" '(lambda ()
                                          (interactive)
                                          (forward-line 1)
                                          (transpose-lines 1)
                                          (forward-line -2)))
  (define-key ldraw-ledit-mode-map "/fe" 'ldraw-ledit-exit)
  (define-key ldraw-ledit-mode-map "\M-fe" 'ldraw-ledit-exit)
  (define-key ldraw-ledit-mode-map "/t" 'ldraw-turn-line)
  (define-key ldraw-ledit-mode-map "\M-t" 'ldraw-turn-line)
  (define-key ldraw-ledit-mode-map "x" 'ldraw-translate-line-x)
  (define-key ldraw-ledit-mode-map "y" 'ldraw-translate-line-y)
  (define-key ldraw-ledit-mode-map "z" 'ldraw-translate-line-z)
  (define-key ldraw-ledit-mode-map "c" 'ldraw-change-colour-line)
  (define-key ldraw-ledit-mode-map "i" 'ldraw-insert-part-line)
  (define-key ldraw-ledit-mode-map "a"
    '(lambda (&optional n)
       (interactive "P")
       (ldraw-rotate-line-reverse (ldraw-make-rotation-matrix (list 0 1 0) 90) n)))
  (define-key ldraw-ledit-mode-map "\M-a"
    '(lambda (&optional n)
       (interactive "P")
       (ldraw-rotate-line-reverse (ldraw-make-rotation-matrix (list 0 1 0) -90) n)))
  (define-key ldraw-ledit-mode-map [menu-bar] (make-sparse-keymap))
  (define-key ldraw-ledit-mode-map [menu-bar ledit]
    (cons "LEdit" (make-sparse-keymap "LEdit")))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-ledit-exit]
    '("Exit LEdit Emulator" . ldraw-ledit-exit))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-turn-line]
    '("Turn Line" . ldraw-turn-line))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-translate-line-x]
    '("Offset Line along X-axis" . ldraw-translate-line-x))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-translate-line-y]
    '("Offset Line along Y-axis" . ldraw-translate-line-y))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-translate-line-z]
    '("Offset Line along Z-axis" . ldraw-translate-line-z))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-change-colour-line]
    '("Change Colour" . ldraw-change-colour-line))
  (define-key ldraw-ledit-mode-map [menu-bar ledit ldraw-insert-part-line]
    '("Insert part" . ldraw-insert-part-line))
  )

(if ldraw-search-mode-map
    ()
  (setq ldraw-search-mode-map (make-sparse-keymap))
  (define-key ldraw-search-mode-map "\C-c\C-p" 'ldraw-search-fetch-part-image-from-web)
  (define-key ldraw-search-mode-map [return] 'ldraw-search-select-part)
  (define-key ldraw-search-mode-map [delete] 'ldraw-search-exit)
  (define-key ldraw-search-mode-map [backspace] 'ldraw-search-exit)
  )

(defface ldraw-x-face '((((class color)
			      (background dark))
			     (:foreground "light blue"))
			    (((class color)
			      (background light))
			     (:foreground "MidnightBlue"))
			    (t (:italic nil)))
  "X coordinate.")

(defface ldraw-y-face '((((class color)
			      (background dark))
			     (:foreground "pink"))
			    (((class color)
			      (background light))
			     (:foreground "firebrick"))
			    (t (:italic nil)))
  "Y coordinate.")

(defface ldraw-z-face '((((class color)
			      (background dark))
			     (:foreground "pale green"))
			    (((class color)
			      (background light))
			     (:foreground "dark green"))
			    (t (:italic nil)))
  "Z coordinate.")

(defface ldraw-colour-face '((((class color) (background dark))
			      (:foreground "LightSkyBlue"))
			     (((class color) (background light))
			      (:foreground "Blue"))
			     (t (:italic nil)))
  "Colour face.")

(defvar ldraw-x-face 'ldraw-x-face "")
(defvar ldraw-y-face 'ldraw-y-face "")
(defvar ldraw-z-face 'ldraw-z-face "")
(defvar ldraw-colour-face 'ldraw-colour-face "")

(defconst ldraw-font-lock-keywords
  (if (> emacs-major-version 19)
      '(
        ;; The name of the model is in the first line of the file
        ("\\` *0 \\(.*\\)" 1 font-lock-constant-face)
        ;; "Standard headers"
        ("^ *0 *\\(Name: .*\\)" 1 font-lock-constant-face)
        ("^ *0 *\\(Author: .*\\)" 1 font-lock-constant-face)
        ("^ *0 *\\(Un-Official Element\\|Unofficial Element\\)" 1 font-lock-constant-face)
        ;; Various built-in thingeys
        ("^ *0 \\(STEP\\|PAUSE\\|SAVE\\|CLEAR\\) *$" 1 font-lock-builtin-face)
        ("^ *0 \\(FILE\\|WRITE\\|PRINT\\) *\\(.*\\)$" (1 font-lock-builtin-face) (2 font-lock-string-face))
        ;; 1: Part
        ("^ *1 +\\([0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +\\([-.eE0-9]+\\) +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +\\([-.eE0-9]+\\) +\\([-\\.~#a-zA-Z0-9]*\\)"
         (1 ldraw-colour-face)
         (2 ldraw-x-face)  (3 ldraw-y-face)  (4 ldraw-z-face)
         (5 font-lock-function-name-face)
         (6 font-lock-function-name-face)
         (7 font-lock-function-name-face)
         (8 font-lock-string-face))
        ;; 2: Line
        ("^ *2 +\\([0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\)"
         (1 ldraw-colour-face)
         (2 ldraw-x-face)  (3 ldraw-y-face)  (4 ldraw-z-face)
         (5 ldraw-x-face)  (6 ldraw-y-face)  (7 ldraw-z-face))
        ;; 3: Triangle
        ("^ *3 +\\([0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\)"
         (1 ldraw-colour-face)
         (2 ldraw-x-face)  (3 ldraw-y-face)  (4 ldraw-z-face)
         (5 ldraw-x-face)  (6 ldraw-y-face)  (7 ldraw-z-face)
         (8 ldraw-x-face)  (9 ldraw-y-face)  (10 ldraw-z-face))
        ;; 4: Quadilateral
        ("^ *4 +\\([0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\)"
         (1 ldraw-colour-face)
         (2 ldraw-x-face)  (3 ldraw-y-face)  (4 ldraw-z-face)
         (5 ldraw-x-face)  (6 ldraw-y-face)  (7 ldraw-z-face)
         (8 ldraw-x-face)  (9 ldraw-y-face)  (10 ldraw-z-face)
         (11 ldraw-x-face) (12 ldraw-y-face) (13 ldraw-z-face))
        ;; 5: Conditional line
        ("^ *5 +\\([0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\) +\\([-.eE0-9]+\\)"
         (1 ldraw-colour-face)
         (2 ldraw-x-face)  (3 ldraw-y-face)  (4 ldraw-z-face)
         (5 ldraw-x-face)  (6 ldraw-y-face)  (7 ldraw-z-face)
         (8 ldraw-x-face)  (9 ldraw-y-face)  (10 ldraw-z-face)
         (11 ldraw-x-face) (12 ldraw-y-face) (13 ldraw-z-face))
        ;; Nag the user if the format of a line is incorrect
        ("^ *[12345] \\(.*\\)" 1 font-lock-warning-face)
        ;; Any comment
        ("^ *0 \\(.*\\)" 1 font-lock-comment-face))
    '(
      ;; The name of the model is in the first line of the file
      ("\\` *0 \\(.*\\)" 1 font-lock-type-face)
      ;; "Standard headers"
      ("^ *0 *\\(Name: .*\\)" 1 font-lock-type-face)
      ("^ *0 *\\(Author: .*\\)" 1 font-lock-type-face)
      ("^ *0 *\\(Un-Official Element\\|Unofficial Element\\)" 1 font-lock-type-face)
      ;; Various built-in thingeys
      ("^ *0 \\(STEP\\|PAUSE\\|SAVE\\|CLEAR\\) *$" 1 font-lock-reference-face)
      ("^ *0 \\(FILE\\|WRITE\\|PRINT\\) *\\(.*\\)$" (1 font-lock-reference-face) (2 font-lock-string-face))
      ;; 1: Part
      ("^ *1 +[0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +\\([-\\.~#a-zA-Z0-9]*\\)" 1 font-lock-string-face)
      ;; 2: Line
      ("^ *2 +\\([0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+\\)" 1 font-lock-function-name-face)
      ;; 3: Triangle
      ("^ *3 +\\([0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+\\)" 1 font-lock-function-name-face)
      ;; 4: Quadilateral
      ("^ *4 +\\([0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+\\)" 1 font-lock-function-name-face)
      ;; 5: Conditional line
      ("^ *5 +\\([0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+ +[-.eE0-9]+\\)" 1 font-lock-function-name-face)
      ;; Nag the user if the format of a line is incorrect
      ("^ *[12345] \\(.*\\)" 1 font-lock-comment-face)
      ;; Any comment
      ("^ *0 \\(.*\\)" 1 font-lock-comment-face)))
  "Additional expressions to highlight in LDraw mode.")

;; From Don Heyse
(defun ldraw-launch-viewer ()
  "This is a command to launch an external viewer on the model file."
  (interactive)
  (let ((w32-start-process-show-window t))
    (start-process "ldraw-viewer-process" "*ldrawviewer*"
                   ldraw-viewer-path ldraw-viewer-args buffer-file-name)
    )
  )

(defun ldraw-significant (n)
  "Check if float n is significantly larger than zero."
  (>= (abs n) (exp (* (- ldraw-number-of-decimal-places) (log 10)))))

(defun ldraw-vector-significant (v)
  "Check if a vector is significantly larger than the zero vector."
  (or (ldraw-significant (nth 0 v))
      (ldraw-significant (nth 1 v))
      (ldraw-significant (nth 2 v))))

(defun ldraw-vector-subtraction (v1 v2)
  "Returns v1-v2."
  (list (- (nth 0 v1) (nth 0 v2))
        (- (nth 1 v1) (nth 1 v2))
        (- (nth 2 v1) (nth 2 v2))))

(defun ldraw-vectors-different (v1 v2)
  "Check if two vectors are significantly different."
  (ldraw-vector-significant (ldraw-vector-subtraction v1 v2)))

(defun ldraw-strip-trailing-zero (arg)
  ""
  (if (string-match "\\.[1-9]*\\(0+\\)$" arg)
      (setq arg (substring arg 0 (match-beginning 1))))
  (if (string-match "\\.$" arg)
      (setq arg (substring arg 0 (match-beginning 0))))
  arg)

(defun ldraw-linep ()
  "Return non-nil if there is an LDraw imperative on the line."
  (save-excursion
    (beginning-of-line)
                                        ;    (re-search-forward "\\<" (save-excursion
                                        ;    (save-excursion
                                        ;    (end-of-line)
                                        ;    (point)) t nil)))
    (looking-at " *[0-5]\\>")))

(defun ldraw-repeat-function (fun &optional n)
  "Repeat function over some lines.
Calling the function with no arguments applies the function to the
current line.  With an empty prefix argument, all lines.  A positive
argument n means n lines forward, and analogous for a negative
argument."
  ;; No argument; apply to this line only
  (if (not n)
      (if (ldraw-linep)
          (funcall fun))
    (cond ((listp n)
           ;; Empty argument; apply to all lines
           (progn
             (beginning-of-buffer)
             (while 
                 (progn 
                   (if (ldraw-linep)
                       (funcall fun))
                   (end-of-line)
                   (= (forward-line) 0)))))
          ((> n 0)
           ;; Clean n lines forward
           (while (> (setq n (1- n)) -1)
             (progn 
               (if (ldraw-linep)
                   (funcall fun))
               (forward-line))))
          ((< n 0)
           ;; Clean n lines backward
           (while (< (setq n (1+ n)) 1)
             (progn
               (forward-line -1)
               (if (ldraw-linep)
                   (funcall fun))))))))

(defun ldraw-matrix-determinant (A)
  ""
  (+ (* (nth 0 A) (- (* (nth 4 A) (nth 8 A)) (* (nth 5 A) (nth 7 A))))
     (* (nth 1 A) (- (* (nth 5 A) (nth 6 A)) (* (nth 3 A) (nth 8 A))))
     (* (nth 2 A) (- (* (nth 3 A) (nth 7 A)) (* (nth 4 A) (nth 6 A))))))

(defun ldraw-matrix-multiplication (A B &optional reverse)
  ""
  (if reverse (progn (setq dummy A)
                     (setq A B)
                     (setq B dummy)))
  (list (+ (* (nth 0 B) (nth 0 A)) (* (nth 3 B) (nth 1 A)) (* (nth 6 B) (nth 2 A)))
        (+ (* (nth 1 B) (nth 0 A)) (* (nth 4 B) (nth 1 A)) (* (nth 7 B) (nth 2 A)))
        (+ (* (nth 2 B) (nth 0 A)) (* (nth 5 B) (nth 1 A)) (* (nth 8 B) (nth 2 A)))

        (+ (* (nth 0 B) (nth 3 A)) (* (nth 3 B) (nth 4 A)) (* (nth 6 B) (nth 5 A)))
        (+ (* (nth 1 B) (nth 3 A)) (* (nth 4 B) (nth 4 A)) (* (nth 7 B) (nth 5 A)))
        (+ (* (nth 2 B) (nth 3 A)) (* (nth 5 B) (nth 4 A)) (* (nth 8 B) (nth 5 A)))

        (+ (* (nth 0 B) (nth 6 A)) (* (nth 3 B) (nth 7 A)) (* (nth 6 B) (nth 8 A)))
        (+ (* (nth 1 B) (nth 6 A)) (* (nth 4 B) (nth 7 A)) (* (nth 7 B) (nth 8 A)))
        (+ (* (nth 2 B) (nth 6 A)) (* (nth 5 B) (nth 7 A)) (* (nth 8 B) (nth 8 A)))))

(defun ldraw-matrix-vector-multiplication (v m)
  ""
  (list (+ (* (nth 0 v) (nth 0 m)) (* (nth 1 v) (nth 1 m)) (* (nth 2 v) (nth 2 m)))
        (+ (* (nth 0 v) (nth 3 m)) (* (nth 1 v) (nth 4 m)) (* (nth 2 v) (nth 5 m)))
        (+ (* (nth 0 v) (nth 6 m)) (* (nth 1 v) (nth 7 m)) (* (nth 2 v) (nth 8 m)))))

(defun ldraw-extract-matrix4-from-line (line)
  ""
  (if (and line
           (= 1 (car line)))
      (list (nth  5 line) (nth  6 line) (nth  7 line) (nth  2 line) 
            (nth  8 line) (nth  9 line) (nth 10 line) (nth  3 line) 
            (nth 11 line) (nth 12 line) (nth 13 line) (nth  4 line)
            0 0 0 1)
    line))

(defun ldraw-extract-line-from-matrix4 (A)
  ""
  (list (nth  3 A) (nth  7 A) (nth 11 A)
        (nth  0 A) (nth  1 A) (nth  2 A)
        (nth  4 A) (nth  5 A) (nth  6 A)
        (nth  8 A) (nth  9 A) (nth 10 A)))

(defun ldraw-matrix4-multiplication (A B &optional reverse)
  ""
  (if reverse (progn (setq dummy A)
                     (setq A B)
                     (setq B dummy)))
  (list (+ (* (nth 0 B) (nth 0 A)) (* (nth 4 B) (nth 1 A)) (* (nth  8 B) (nth 2 A)) (* (nth 12 B) (nth 3 A)))
        (+ (* (nth 1 B) (nth 0 A)) (* (nth 5 B) (nth 1 A)) (* (nth  9 B) (nth 2 A)) (* (nth 13 B) (nth 3 A)))
        (+ (* (nth 2 B) (nth 0 A)) (* (nth 6 B) (nth 1 A)) (* (nth 10 B) (nth 2 A)) (* (nth 14 B) (nth 3 A)))
        (+ (* (nth 3 B) (nth 0 A)) (* (nth 7 B) (nth 1 A)) (* (nth 11 B) (nth 2 A)) (* (nth 15 B) (nth 3 A)))

        (+ (* (nth 0 B) (nth 4 A)) (* (nth 4 B) (nth 5 A)) (* (nth  8 B) (nth 6 A)) (* (nth 12 B) (nth 7 A)))
        (+ (* (nth 1 B) (nth 4 A)) (* (nth 5 B) (nth 5 A)) (* (nth  9 B) (nth 6 A)) (* (nth 13 B) (nth 7 A)))
        (+ (* (nth 2 B) (nth 4 A)) (* (nth 6 B) (nth 5 A)) (* (nth 10 B) (nth 6 A)) (* (nth 14 B) (nth 7 A)))
        (+ (* (nth 3 B) (nth 4 A)) (* (nth 7 B) (nth 5 A)) (* (nth 11 B) (nth 6 A)) (* (nth 15 B) (nth 7 A)))

        (+ (* (nth 0 B) (nth 8 A)) (* (nth 4 B) (nth 9 A)) (* (nth  8 B) (nth 10 A)) (* (nth 12 B) (nth 11 A)))
        (+ (* (nth 1 B) (nth 8 A)) (* (nth 5 B) (nth 9 A)) (* (nth  9 B) (nth 10 A)) (* (nth 13 B) (nth 11 A)))
        (+ (* (nth 2 B) (nth 8 A)) (* (nth 6 B) (nth 9 A)) (* (nth 10 B) (nth 10 A)) (* (nth 14 B) (nth 11 A)))
        (+ (* (nth 3 B) (nth 8 A)) (* (nth 7 B) (nth 9 A)) (* (nth 11 B) (nth 10 A)) (* (nth 15 B) (nth 11 A)))

        (+ (* (nth 0 B) (nth 12 A)) (* (nth 4 B) (nth 13 A)) (* (nth  8 B) (nth 14 A)) (* (nth 12 B) (nth 15 A)))
        (+ (* (nth 1 B) (nth 12 A)) (* (nth 5 B) (nth 13 A)) (* (nth  9 B) (nth 14 A)) (* (nth 13 B) (nth 15 A)))
        (+ (* (nth 2 B) (nth 12 A)) (* (nth 6 B) (nth 13 A)) (* (nth 10 B) (nth 14 A)) (* (nth 14 B) (nth 15 A)))
        (+ (* (nth 3 B) (nth 12 A)) (* (nth 7 B) (nth 13 A)) (* (nth 11 B) (nth 14 A)) (* (nth 15 B) (nth 15 A)))))

(defun ldraw-rotate-line-matrix4 (line A &optional reverse)
  ""
  (if (and line
           (= 1 (car line)))
      (progn
        (setq colour (car (cdr line)))
        (setq part (last line))
        (append (list 1 colour)
                (ldraw-extract-line-from-matrix4
                 (ldraw-matrix4-multiplication A 
                                               (ldraw-extract-matrix4-from-line line)
                                               reverse))
                part))
    line))
  
(defun ldraw-normalize-vector (v)
  ""
  (setq sum (sqrt (+ (expt (car v) 2)
                     (expt (car (cdr v)) 2)
                     (expt (car (cdr (cdr v))) 2))))
  (list (/ (car v) sum)
        (/ (car (cdr v)) sum)
        (/ (car (cdr (cdr v))) sum)))
  
(defun ldraw-vector-cross-product (v1 v2) 
  ""
  (list (- (* (nth 1 v1) (nth 2 v2)) (* (nth 2 v1) (nth 1 v2)))
        (- (* (nth 2 v1) (nth 0 v2)) (* (nth 0 v1) (nth 2 v2)))
        (- (* (nth 0 v1) (nth 1 v2)) (* (nth 1 v1) (nth 0 v2)))))

(defun ldraw-rotation-matrix (v)
  "Make a matrix which corresponds to rotating a line pointing upwards parallell to v"
  (setq v2 (ldraw-normalize-vector (list (+ (nth 0 v)) (+ (nth 1 v)) (+ (nth 2 v)))))
  (setq v1 (ldraw-normalize-vector (ldraw-vector-cross-product v2 ldraw-bezier-rotate-vector)))
  (setq v3 (ldraw-normalize-vector (ldraw-vector-cross-product v1 v2)))
  (list (+ (nth 0 v1)) (+ (nth 0 v2))  (+ (nth 0 v3)) 
        (+ (nth 1 v1)) (+ (nth 1 v2))  (+ (nth 1 v3)) 
        (+ (nth 2 v1)) (+ (nth 2 v2))  (+ (nth 2 v3))))

(defun ldraw-parse-current-line ()
  "Parse current line."
  (if (not (ldraw-linep))
      nil
    (save-excursion
      (beginning-of-line)
      (skip-chars-forward "\t ")
      (setq line-type (string-to-number
                       (buffer-substring
                        (point) (progn (re-search-forward "\\>") (point)))))
      (beginning-of-line)
      (mapcar '(lambda (arg) (skip-chars-forward "\t ")
                 (cond ((= arg 0)       ;integer
                        (string-to-number
                         (buffer-substring
                          (point) (progn 
                                    (re-search-forward "\\>"
                                                       (save-excursion
                                                         (end-of-line)
                                                         (point))
                                                       t nil)
                                    (point)))))
                       ((= arg 1)       ;float
                        (string-to-number
                         (buffer-substring (point) (progn 
                                                     (re-search-forward "\\>")
                                                     (point)))))
                       ((= arg 2)       ;trailing string
                        ;; Any text to copy?
                        (if (< (save-excursion (skip-chars-forward "\t "))
                               (- (save-excursion (end-of-line) (point)) (point)))
                            (buffer-substring-no-properties
                             (point) (progn
                                       (end-of-line)
                                       (skip-chars-backward "\t ")
                                       (point)))
                          nil))))
              ;; How to parse the various line types
              (aref [(0 2)              ; 0 Comment
                     (0 0 1 1 1 1 1 1 1 1 1 1 1 1 2) ; 1 Part
                     (0 0 1 1 1 1 1 1)  ; 2 Line 
                     (0 0 1 1 1 1 1 1 1 1 1) ; 3 Triangle
                     (0 0 1 1 1 1 1 1 1 1 1 1 1 1) ; 4 Quadilateral
                     (0 0 1 1 1 1 1 1 1 1 1 1 1 1) ; 5 Conditional Line
                     ] line-type)))))

(defun ldraw-write-current-line (line)
  "Write out a line."
  (insert (mapconcat '(lambda (arg)
                        (if (numberp arg)
                            (progn
                              ;; Strip surplus trailing zeros
                              (setq arg (ldraw-strip-trailing-zero
                                         (format
                                          (concat
                                           "%." (number-to-string ldraw-number-of-decimal-places) "f")
                                          arg)))
                              ;; Make sure we don't return a number to `mapconcat'
                              (if (numberp arg)
                                  (setq arg (number-to-string arg)))
                              ;; Make sure we don't have a "-0" entry
                              (if (= (string-to-number arg) 0)
                                  "0"
                                arg))
                          arg))
                     line " ")))

(defun ldraw-erase-current-line ()
  ""
  (beginning-of-line)
  (skip-chars-forward "\t ")
  (delete-region (point) (save-excursion (end-of-line) (point))))

(defun ldraw-blank-out-current-line ()
  "Totally blank out, erase this line.
This function removes the CR as well."
  (beginning-of-line)
  (delete-region (point) (save-excursion (forward-line 1) (point)))
                                        ;  (backward-char)
  )

(defun ldraw-new-part-name (name)
  ""
  (setq this-line (ldraw-parse-current-line))
  (if (and this-line
           (= (car this-line) 1))
      (progn
        (ldraw-erase-current-line)
        (ldraw-write-current-line
         (append (delq (car (last this-line)) this-line) (list name))))))

(defun ldraw-part-line-to-insert ()
  "Get the part name and position of the current part.

Returns a part line with the name and position of the current part, but
with a normalized transformation matrix.  This is part of the function
which emulates the LEdit \"i\" command."
  (setq this-line (ldraw-parse-current-line))
  (if (and this-line
           (= 1 (car this-line)))
      (append (list (car this-line)
                    (nth 1 this-line)
                    (nth 2 this-line)
                    (nth 3 this-line)
                    (nth 4 this-line))
              '(1 0 0 0 1 0 0 0 1)
              (last this-line))
    (list 1 0 0 0 0 1 0 0 0 1 0 0 0 1 "3001.DAT")))

;;; TODO: Handle indentation
(defun ldraw-insert-part-one-line (line)
  "Inserts a new part line beneath the current line."
  (end-of-line)
  (insert "
 ")
  (ldraw-write-current-line line))

(defun ldraw-insert-part-line (&optional n)
  "Mimics the LEdit \"i\" command.

With a positive argument n, insert n copies of the part.  The part
name, position and colour is preserved, but the tranformations matrix
is replaced with unity."
  (interactive "P")
  (setq this-line (ldraw-part-line-to-insert))
  (or (and n (> n 0))
      (setq n 1))
  (while (> (setq n (1- n)) -1)
    (ldraw-insert-part-one-line this-line)))

(defun ldraw-extract-coordinates-type-1-line (line)
  ""
  (reverse (nthcdr 10 (reverse (nthcdr 2 line)))))

(defun ldraw-translate (line offset)
  ""
  (cond ((= (car line) 0) line)
        ((= (car line) 1)
         (progn
           (setq new-line (list (car line)
                                (nth 1 line)
                                (+ (nth 2 line) (nth 0 offset))
                                (+ (nth 3 line) (nth 1 offset))
                                (+ (nth 4 line) (nth 2 offset))))
           (append new-line (nthcdr 5 line))))
        ((= (car line) 2)
         (list (car line)
               (nth 1 line)
               (+ (nth 2 line) (nth 0 offset))
               (+ (nth 3 line) (nth 1 offset))
               (+ (nth 4 line) (nth 2 offset))
               (+ (nth 5 line) (nth 0 offset))
               (+ (nth 6 line) (nth 1 offset))
               (+ (nth 7 line) (nth 2 offset))))
        ((= (car line) 3)
         (list (car line)
               (nth 1 line)
               (+ (nth 2 line) (nth 0 offset))
               (+ (nth 3 line) (nth 1 offset))
               (+ (nth 4 line) (nth 2 offset))
               (+ (nth 5 line) (nth 0 offset))
               (+ (nth 6 line) (nth 1 offset))
               (+ (nth 7 line) (nth 2 offset))
               (+ (nth 8 line) (nth 0 offset))
               (+ (nth 9 line) (nth 1 offset))
               (+ (nth 10 line) (nth 2 offset))))
        ((or (= (car line) 4) (= (car line) 5))
         (list (car line)
               (nth 1 line)
               (+ (nth 2 line) (nth 0 offset))
               (+ (nth 3 line) (nth 1 offset))
               (+ (nth 4 line) (nth 2 offset))
               (+ (nth 5 line) (nth 0 offset))
               (+ (nth 6 line) (nth 1 offset))
               (+ (nth 7 line) (nth 2 offset))
               (+ (nth 8 line) (nth 0 offset))
               (+ (nth 9 line) (nth 1 offset))
               (+ (nth 10 line) (nth 2 offset))
               (+ (nth 11 line) (nth 0 offset))
               (+ (nth 12 line) (nth 1 offset))
               (+ (nth 13 line) (nth 2 offset))))))

(defun ldraw-rotate (line m &optional reverse)
  ""
  (cond ((= (car line) 0) line)
        ((= (car line) 1)
         (progn
           (setq name (nth 14 line))
           (setq m2 (delq (nth 14 line) (nthcdr 5 line)))
           (setq init (list (car line)
                            (nth 1 line)))
           (setq init (append init
			      (if reverse (list (nth 2 line)
						(nth 3 line)
						(nth 4 line))
				(ldraw-matrix-vector-multiplication (list (nth 2 line)
									  (nth 3 line)
									  (nth 4 line)) m))
                              (ldraw-matrix-multiplication m m2 reverse)))
           (append init (list name))))
        ((= (car line) 2)
         (progn
           (setq init (list (car line) (nth 1 line)))
           (append init
                   (ldraw-matrix-vector-multiplication (list (nth 2 line)
                                                             (nth 3 line)
                                                             (nth 4 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 5 line)
                                                             (nth 6 line)
                                                             (nth 7 line)) m))))
        ((= (car line) 3)
         (progn
           (setq init (list (car line) (nth 1 line)))
           (append init
                   (ldraw-matrix-vector-multiplication (list (nth 2 line)
                                                             (nth 3 line)
                                                             (nth 4 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 5 line)
                                                             (nth 6 line)
                                                             (nth 7 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 8 line)
                                                             (nth 9 line)
                                                             (nth 10 line)) m))))
        ((or (= (car line) 4) (= (car line) 5))
         (progn
           (setq init (list (car line) (nth 1 line)))
           (append init
                   (ldraw-matrix-vector-multiplication (list (nth 2 line)
                                                             (nth 3 line) 
                                                             (nth 4 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 5 line)
                                                             (nth 6 line)
                                                             (nth 7 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 8 line)
                                                             (nth 9 line)
                                                             (nth 10 line)) m)
                   (ldraw-matrix-vector-multiplication (list (nth 11 line)
                                                             (nth 12 line)
                                                             (nth 13 line)) m))))))

(defun ldraw-get-current-line-centre ()
  ""
  (setq this-line (ldraw-parse-current-line))
  (if (or (not this-line)
          (= (car this-line) 0))
      ldraw-turn-centre
    (list (nth 2 this-line)
          (nth 3 this-line)
          (nth 4 this-line))))

(defun ldraw-prompt-angle (prompt)
  ""
  (string-to-number (read-string prompt)))

(defun ldraw-make-rotation-matrix (v a)
  ""
  (setq sina (sin (- (* (/ pi 360) a))))
  (setq w (cos (- (* (/ pi 360) a))))
  (setq x (* sina (nth 0 v)))
  (setq y (* sina (nth 1 v)))
  (setq z (* sina (nth 2 v)))
  (list (- 1 (* 2 (+ (* y y) (* z z))))
        (* 2 (+ (* x y) (* w z)))
        (* 2 (- (* x z) (* w y)))
        (* 2 (- (* x y) (* w z)))
        (- 1 (* 2 (+ (* x x) (* z z))))
        (* 2 (+ (* y z) (* w x)))
        (* 2 (+ (* x z) (* w y)))
        (* 2 (- (* y z) (* w x)))
        (- 1 (* 2 (+ (* x x) (* y y))))))

(defun ldraw-translate-current-line (offset)
  ""
  (setq line (ldraw-parse-current-line))
  (if (= (car line) 0)
      ;; Comment; ignore
      ()
    (ldraw-erase-current-line)
    (ldraw-write-current-line (ldraw-translate line offset))))

(defun ldraw-rotate-current-line (m)
  ""
  (setq line (ldraw-parse-current-line))
  (if (or (not line)
          (= (car line) 0))
      ;; Comment; ignore
      ()
    (ldraw-erase-current-line)
    ;; Make sure we turn round the centre point, `ldraw-turn-centre'.
    (ldraw-write-current-line (ldraw-translate
                               (ldraw-rotate
                                (ldraw-translate line (mapcar '- ldraw-turn-centre)) m)
                               ldraw-turn-centre))))

(defun ldraw-rotate-current-line-reverse (m)
  ""
  (setq line (ldraw-parse-current-line))
  (if (and line
           (= (car line) 1))
      ;; Only applies to type 1 lines.
      (progn
        (ldraw-erase-current-line)
        (ldraw-write-current-line (ldraw-rotate line m t)))))

(defun ldraw-cut-line-by-coordinates (coordinates)
  ""
                                        ;  (message (mapcar 'number-to-string coordinates))
  (setq xa1 (nth 0 coordinates)
        ya1 (nth 1 coordinates)
        za1 (nth 2 coordinates)
        xa2 (nth 3 coordinates)
        ya2 (nth 4 coordinates)
        za2 (nth 5 coordinates)
        tt (- (/ ya1 (float (- ya2 ya1))))
        xa (+ xa1 (* (- xa2 xa1) tt))
        za (+ za1 (* (- za2 za1) tt)))
  (if (> ya1 ya2)
      (list xa 0 za xa2 ya2 za2)
    (list xa1 ya1 za1 xa 0 za)))

(defun ldraw-cut-current-line ()
  ""
  (setq this-line (ldraw-parse-current-line))
  (if (not (or (not this-line)
               (= (car this-line) 0)))
      (cond ((= (car this-line) 1)      ; Part
             (if (> (nth 3 this-line) 0)
                 (ldraw-blank-out-current-line)))
            ((= (car this-line) 2)      ; Line
             (let ((y1 (nth 3 this-line))
                   (y2 (nth 6 this-line)))
               (if (and (> y1 0) (> y2 0))
                   (ldraw-blank-out-current-line)
                 (if (or (> y1 0) (> y2 0))
                     (let ((new-line (append (list (car this-line)
                                                   (nth 1 this-line))
                                             (ldraw-cut-line-by-coordinates (nthcdr 2 this-line)))))
                       (ldraw-erase-current-line)
                       (ldraw-write-current-line new-line)))
		 (forward-line 0))))
            ((= (car this-line) 3)      ; Triangle
             (let* ((y1 (nth 3 this-line))
                    (y2 (nth 6 this-line))
                    (y3 (nth 9 this-line))
                    (below-plane (mapcar '(lambda (arg) (if arg 1 0))
                                         (list (> y1 0) (> y2 0) (> y3 0)))))
               ;; There must be a better way to sum a list!
               (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane)) 3)
                   (ldraw-blank-out-current-line)
                 (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane)) 2)
                     ;; Two of the vertices are below the X-Z-plane.
                     ;; This can be done more efficiently, I'm sure!
                     (progn
                       (cond ((= 0 (car below-plane))
                              (setq x-1 (nth 2 this-line)
                                    y-1 (nth 3 this-line)
                                    z-1 (nth 4 this-line)
                                    x-2 (nth 5 this-line)
                                    y-2 (nth 6 this-line)
                                    z-2 (nth 7 this-line)
                                    x-3 (nth 8 this-line)
                                    y-3 (nth 9 this-line)
                                    z-3 (nth 10 this-line)))
                             ((= 0 (nth 1 below-plane))
                              (setq x-2 (nth 2 this-line)
                                    y-2 (nth 3 this-line)
                                    z-2 (nth 4 this-line)
                                    x-1 (nth 5 this-line)
                                    y-1 (nth 6 this-line)
                                    z-1 (nth 7 this-line)
                                    x-3 (nth 8 this-line)
                                    y-3 (nth 9 this-line)
                                    z-3 (nth 10 this-line)))
                             ((= 0 (nth 2 below-plane))
                              (setq x-2 (nth 2 this-line)
                                    y-2 (nth 3 this-line)
                                    z-2 (nth 4 this-line)
                                    x-3 (nth 5 this-line)
                                    y-3 (nth 6 this-line)
                                    z-3 (nth 7 this-line)
                                    x-1 (nth 8 this-line)
                                    y-1 (nth 9 this-line)
                                    z-1 (nth 10 this-line))))
                       (setq cut1 (ldraw-cut-line-by-coordinates (list x-1 y-1 z-1 x-2 y-2 z-2))
                             cut2 (ldraw-cut-line-by-coordinates (list x-1 y-1 z-1 x-3 y-3 z-3)))
                       (ldraw-erase-current-line)
                       (ldraw-write-current-line (append (list (car this-line)
                                                               (nth 1 this-line))
                                                         (list x-1 y-1 z-1)
                                                         (nthcdr 3 cut1)
                                                         (nthcdr 3 cut2)))
                       (if ldraw-cut-edge
                           (progn
                             (setq colour (if (= (nth 1 this-line) 16) 24 (nth (% (nth 1 this-line) 16)
                                                                               ldraw-edge-colour-table)))
                             (ldraw-insert-part-one-line (append (list 2 colour)
                                                                 (nthcdr 3 cut1)
                                                                 (nthcdr 3 cut2))))))
                   (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane)) 1)
                       ;; One of the vertices is below the X-Z-plane.
                       ;; This can be done more efficiently, I'm sure!
                       (progn
                         (cond ((= 1 (car below-plane))
                                (setq x-1 (nth 2 this-line)
                                      y-1 (nth 3 this-line)
                                      z-1 (nth 4 this-line)
                                      x-2 (nth 5 this-line)
                                      y-2 (nth 6 this-line)
                                      z-2 (nth 7 this-line)
                                      x-3 (nth 8 this-line)
                                      y-3 (nth 9 this-line)
                                      z-3 (nth 10 this-line)))
                               ((= 1 (nth 1 below-plane))
                                (setq x-2 (nth 2 this-line)
                                      y-2 (nth 3 this-line)
                                      z-2 (nth 4 this-line)
                                      x-1 (nth 5 this-line)
                                      y-1 (nth 6 this-line)
                                      z-1 (nth 7 this-line)
                                      x-3 (nth 8 this-line)
                                      y-3 (nth 9 this-line)
                                      z-3 (nth 10 this-line)))
                               ((= 1 (nth 2 below-plane))
                                (setq x-2 (nth 2 this-line)
                                      y-2 (nth 3 this-line)
                                      z-2 (nth 4 this-line)
                                      x-3 (nth 5 this-line)
                                      y-3 (nth 6 this-line)
                                      z-3 (nth 7 this-line)
                                      x-1 (nth 8 this-line)
                                      y-1 (nth 9 this-line)
                                      z-1 (nth 10 this-line))))
                         (setq cut1 (ldraw-cut-line-by-coordinates (list x-2 y-2 z-2 x-1 y-1 z-1))
                               cut2 (ldraw-cut-line-by-coordinates (list x-3 y-3 z-3 x-1 y-1 z-1)))
                         (ldraw-erase-current-line)
                         (ldraw-write-current-line (append (list 4 (nth 1 this-line))
                                                           (list x-2 y-2 z-2 x-3 y-3 z-3)
                                                           (nthcdr 3 cut1)
                                                           (nthcdr 3 cut2)))
                         (if ldraw-cut-edge
                             (progn
                               (setq colour (if (= (nth 1 this-line) 16) 24 (nth (% (nth 1 this-line) 16)
                                                                                 ldraw-edge-colour-table)))
                               (ldraw-insert-part-one-line (append (list 2 colour)
                                                                   (nthcdr 3 cut1)
                                                                   (nthcdr 3 cut2))))))))
		 (forward-line 0))))
    
            ((= (car this-line) 4)      ; Quadilateral
             (let* ((y1 (nth 3 this-line))
                    (y2 (nth 6 this-line))
                    (y3 (nth 9 this-line))
                    (y4 (nth 12 this-line))
                    (below-plane (mapcar '(lambda (arg) (if arg 1 0))
                                         (list (> y1 0) (> y2 0) (> y3 0) (> y4 0)))))
               ;; There must be a better way to sum a list!
               (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane) (nth 3 below-plane)) 4)
                   (ldraw-blank-out-current-line)
                 (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane) (nth 3 below-plane)) 3)
                     ;; Three of the vertices are below the X-Z-plane.
                     ;; This can be done more efficiently, I'm sure!
                     (progn
                       (cond ((= 0 (car below-plane))
                              (setq x-1 (nth 2 this-line)
                                    y-1 (nth 3 this-line)
                                    z-1 (nth 4 this-line)
                                    x-2 (nth 5 this-line)
                                    y-2 (nth 6 this-line)
                                    z-2 (nth 7 this-line)
                                    x-3 (nth 11 this-line)
                                    y-3 (nth 12 this-line)
                                    z-3 (nth 13 this-line)))
                             ((= 0 (nth 1 below-plane))
                              (setq x-2 (nth 2 this-line)
                                    y-2 (nth 3 this-line)
                                    z-2 (nth 4 this-line)
                                    x-1 (nth 5 this-line)
                                    y-1 (nth 6 this-line)
                                    z-1 (nth 7 this-line)
                                    x-3 (nth 8 this-line)
                                    y-3 (nth 9 this-line)
                                    z-3 (nth 10 this-line)))
                             ((= 0 (nth 2 below-plane))
                              (setq x-3 (nth 5 this-line)
                                    y-3 (nth 6 this-line)
                                    z-3 (nth 7 this-line)
                                    x-1 (nth 8 this-line)
                                    y-1 (nth 9 this-line)
                                    z-1 (nth 10 this-line)
                                    x-2 (nth 11 this-line)
                                    y-2 (nth 12 this-line)
                                    z-2 (nth 13 this-line)))
                             ((= 0 (nth 3 below-plane))
                              (setq x-2 (nth 2 this-line)
                                    y-2 (nth 3 this-line)
                                    z-2 (nth 4 this-line)
                                    x-3 (nth 8 this-line)
                                    y-3 (nth 9 this-line)
                                    z-3 (nth 10 this-line)
                                    x-1 (nth 11 this-line)
                                    y-1 (nth 12 this-line)
                                    z-1 (nth 13 this-line))))
                       (setq cut1 (ldraw-cut-line-by-coordinates (list x-1 y-1 z-1 x-2 y-2 z-2))
                             cut2 (ldraw-cut-line-by-coordinates (list x-1 y-1 z-1 x-3 y-3 z-3)))
                       (ldraw-erase-current-line)
                       (ldraw-write-current-line (append (list 3 (nth 1 this-line))
                                                         (list x-1 y-1 z-1)
                                                         (nthcdr 3 cut1)
                                                         (nthcdr 3 cut2)))
                       (if ldraw-cut-edge
                           (progn
                             (setq colour (if (= (nth 1 this-line) 16) 24 (nth (% (nth 1 this-line) 16)
                                                                               ldraw-edge-colour-table)))
                             (ldraw-insert-part-one-line (append (list 2 colour)
                                                                 (nthcdr 3 cut1)
                                                                 (nthcdr 3 cut2))))))
                   (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane) (nth 3 below-plane)) 2)
                       ;; Two of the vertices are below the X-Z-plane.
                       ;; This can be done more efficiently, I'm sure!
                       (progn
                         (cond ((and (= 0 (car below-plane)) (= 0 (nth 1 below-plane)))
                                (setq x-1 (nth 2 this-line)
                                      y-1 (nth 3 this-line)
                                      z-1 (nth 4 this-line)
                                      x-2 (nth 5 this-line)
                                      y-2 (nth 6 this-line)
                                      z-2 (nth 7 this-line)
                                      x-3 (nth 8 this-line)
                                      y-3 (nth 9 this-line)
                                      z-3 (nth 10 this-line)
                                      x-4 (nth 11 this-line)
                                      y-4 (nth 12 this-line)
                                      z-4 (nth 13 this-line)))
                               ((and (= 0 (nth 1 below-plane)) (= 0 (nth 2 below-plane)))
                                (setq x-4 (nth 2 this-line)
                                      y-4 (nth 3 this-line)
                                      z-4 (nth 4 this-line)
                                      x-1 (nth 5 this-line)
                                      y-1 (nth 6 this-line)
                                      z-1 (nth 7 this-line)
                                      x-2 (nth 8 this-line)
                                      y-2 (nth 9 this-line)
                                      z-2 (nth 10 this-line)
                                      x-3 (nth 11 this-line)
                                      y-3 (nth 12 this-line)
                                      z-3 (nth 13 this-line)))
                               ((and (= 0 (nth 2 below-plane)) (= 0 (nth 3 below-plane)))
                                (setq x-3 (nth 2 this-line)
                                      y-3 (nth 3 this-line)
                                      z-3 (nth 4 this-line)
                                      x-4 (nth 5 this-line)
                                      y-4 (nth 6 this-line)
                                      z-4 (nth 7 this-line)
                                      x-1 (nth 8 this-line)
                                      y-1 (nth 9 this-line)
                                      z-1 (nth 10 this-line)
                                      x-2 (nth 11 this-line)
                                      y-2 (nth 12 this-line)
                                      z-2 (nth 13 this-line)))
                               ((and (= 0 (nth 3 below-plane)) (= 0 (car below-plane)))
                                (setq x-2 (nth 2 this-line)
                                      y-2 (nth 3 this-line)
                                      z-2 (nth 4 this-line)
                                      x-3 (nth 5 this-line)
                                      y-3 (nth 6 this-line)
                                      z-3 (nth 7 this-line)
                                      x-4 (nth 8 this-line)
                                      y-4 (nth 9 this-line)
                                      z-4 (nth 10 this-line)
                                      x-1 (nth 11 this-line)
                                      y-1 (nth 12 this-line)
                                      z-1 (nth 13 this-line))))
                         (setq cut1 (ldraw-cut-line-by-coordinates (list x-1 y-1 z-1 x-4 y-4 z-4))
                               cut2 (ldraw-cut-line-by-coordinates (list x-2 y-2 z-2 x-3 y-3 z-3)))
                         (ldraw-erase-current-line)
                         (ldraw-write-current-line (append (list 4 (nth 1 this-line))
                                                           (nthcdr 3 cut1)
                                                           (list x-1 y-1 z-1)
                                                           (list x-2 y-2 z-2)
                                                           (nthcdr 3 cut2)))
                         (if ldraw-cut-edge
                             (progn
                               (setq colour (if (= (nth 1 this-line) 16) 24 (nth (% (nth 1 this-line) 16)
                                                                                 ldraw-edge-colour-table)))
                               (ldraw-insert-part-one-line (append (list 2 colour)
                                                                   (nthcdr 3 cut1)
                                                                   (nthcdr 3 cut2))))))
                     (if (= (+ (car below-plane) (nth 1 below-plane) (nth 2 below-plane) (nth 3 below-plane)) 1)
                         ;; One of the vertices is below the X-Z-plane.
                         ;; This can be done more efficiently, I'm sure!
                         (progn
                           (cond ((= 1 (car below-plane))
                                  (setq x-1 (nth 2 this-line)
                                        y-1 (nth 3 this-line)
                                        z-1 (nth 4 this-line)
                                        x-2 (nth 5 this-line)
                                        y-2 (nth 6 this-line)
                                        z-2 (nth 7 this-line)
                                        x-3 (nth 8 this-line)
                                        y-3 (nth 9 this-line)
                                        z-3 (nth 10 this-line)
                                        x-4 (nth 11 this-line)
                                        y-4 (nth 12 this-line)
                                        z-4 (nth 13 this-line)))
                                 ((= 1 (nth 1 below-plane))
                                  (setq x-4 (nth 2 this-line)
                                        y-4 (nth 3 this-line)
                                        z-4 (nth 4 this-line)
                                        x-1 (nth 5 this-line)
                                        y-1 (nth 6 this-line)
                                        z-1 (nth 7 this-line)
                                        x-2 (nth 8 this-line)
                                        y-2 (nth 9 this-line)
                                        z-2 (nth 10 this-line)
                                        x-3 (nth 11 this-line)
                                        y-3 (nth 12 this-line)
                                        z-3 (nth 13 this-line)))
                                 ((= 1 (nth 2 below-plane))
                                  (setq x-3 (nth 2 this-line)
                                        y-3 (nth 3 this-line)
                                        z-3 (nth 4 this-line)
                                        x-4 (nth 5 this-line)
                                        y-4 (nth 6 this-line)
                                        z-4 (nth 7 this-line)
                                        x-1 (nth 8 this-line)
                                        y-1 (nth 9 this-line)
                                        z-1 (nth 10 this-line)
                                        x-2 (nth 11 this-line)
                                        y-2 (nth 12 this-line)
                                        z-2 (nth 13 this-line)))
                                 ((= 1 (nth 3 below-plane))
                                  (setq x-2 (nth 2 this-line)
                                        y-2 (nth 3 this-line)
                                        z-2 (nth 4 this-line)
                                        x-3 (nth 5 this-line)
                                        y-3 (nth 6 this-line)
                                        z-3 (nth 7 this-line)
                                        x-4 (nth 8 this-line)
                                        y-4 (nth 9 this-line)
                                        z-4 (nth 10 this-line)
                                        x-1 (nth 11 this-line)
                                        y-1 (nth 12 this-line)
                                        z-1 (nth 13 this-line))))
                           (setq cut1 (ldraw-cut-line-by-coordinates (list x-4 y-4 z-4 x-1 y-1 z-1))
                                 cut2 (ldraw-cut-line-by-coordinates (list x-2 y-2 z-2 x-1 y-1 z-1)))
                           (ldraw-erase-current-line)
                           (ldraw-write-current-line (append (list 3 (nth 1 this-line))
                                                             (list x-2 y-2 z-2)
                                                             (list x-3 y-3 z-3)
                                                             (list x-4 y-4 z-4)))
                           (ldraw-insert-part-one-line (append (list 4 (nth 1 this-line))
                                                               (list x-2 y-2 z-2)
                                                               (list x-4 y-4 z-4)
                                                               (nthcdr 3 cut1)
                                                               (nthcdr 3 cut2)))
                           (if ldraw-cut-edge
                               (progn
                                 (setq colour (if (= (nth 1 this-line) 16) 24 (nth (% (nth 1 this-line) 16)
                                                                                   ldraw-edge-colour-table)))
                                 (ldraw-insert-part-one-line (append (list 2 colour)
                                                                     (nthcdr 3 cut1)
                                                                     (nthcdr 3 cut2))))))))))))
            ((= (car this-line) 5)      ; Conditional line
             (let ((y1 (nth 3 this-line))
                   (y2 (nth 6 this-line)))
               (if (and (> y1 0) (> y2 0))
                   (ldraw-blank-out-current-line)
                 (if (or (> y1 0) (> y2 0))
                     (let ((new-line (append (list (car this-line)
                                                   (nth 1 this-line))
                                             (ldraw-cut-line-by-coordinates (nthcdr 2 this-line))
                                             (list (nth 8 this-line)
                                                   (nth 9 this-line)
                                                   (nth 10 this-line)
                                                   (nth 11 this-line)
                                                   (nth 12 this-line)
                                                   (nth 13 this-line)))))
                       (ldraw-erase-current-line)
                       (ldraw-write-current-line new-line))
		   (forward-line 0))))))))

(defun ldraw-cut-line (&optional n)
  "Cut the current line below the X-Z-plane.
If the current line is fully above the X-Z-plane, it is ignored.  If the
current line is a part, remove it if it's origin is below the X-Z-plane.

If it is a line, triangle or quadilateral, remove it completely if it
resides fully below the X-Z-plane.  Otherwise, cut it below the
X-Z-plane.  If it originally was a triangle, it may be turned into a
quadilateral.  If it was a quadilateral, it may be turned into a
triangle and a quadilateral.  If the variable `ldraw-cut-edge' is set,
make and addition edge where a triangle or quadilateral was cut."
  (interactive "P")
  (ldraw-repeat-function 'ldraw-cut-current-line n))


(defun ldraw-fetch-a-part-image-from-web (name colour)
  "Fetch part image from the web.
NAME is a string, the part name without an extension.  COLOUR is a
number, the colur number."
  ;; We need William M. Perry's W3 to download an image
  (require 'w3)
                                        ;  Old version for Tom Stangl's image repository
                                        ;  (w3-fetch (concat ldraw-parts-images-web-base
                                        ;                    (nth (% colour 16) ldraw-colour-names) "/" name ".gif")))
  (w3-fetch (concat ldraw-parts-images-web-base name ".gif")))

(defun ldraw-fetch-part-image-from-web-this-line ()
  "Fetch an image of the part on the current line from the web."
  (setq this-line (ldraw-parse-current-line))
  (if (and this-line
           (= (car this-line) 1))
      (ldraw-fetch-a-part-image-from-web
       (file-name-sans-extension (car (last this-line)))
       (car (cdr this-line)))))

(defun ldraw-fetch-part-image-from-web (&optional n)
  "Fetch image(s) of the current part(s).

Uses the part image database located at the URL
`ldraw-parts-images-web-base', and also the colour table
`ldraw-colour-names' to access a part with the correct colour.

You'll need to have William M. Perry's `w3' installed for this fuction
to work.

This function is not too robust.  If the image for a particular file
does not exist, `w3' will render the error page, rather than ignore the
request."
  (interactive "P")
  (ldraw-repeat-function 'ldraw-fetch-part-image-from-web-this-line n))


(defun ldraw-bfc-reverse-this-line ()
  "Reverse the orientation of the current part(s)."
  (setq this-line (ldraw-parse-current-line))
  ;; Apply only to triangles and quads
  (if (or (= (car this-line) 3)
          (= (car this-line) 4))
      (if (=(car this-line) 3)
          ;; We have a triangle
          (progn
            (ldraw-erase-current-line)
            (ldraw-write-current-line (list (car this-line)
                                            (nth 1 this-line)
                                            
                                            (nth 2 this-line)
                                            (nth 3 this-line)
                                            (nth 4 this-line)

                                            (nth 8 this-line)
                                            (nth 9 this-line)
                                            (nth 10 this-line)
                                            
                                            (nth 5 this-line)
                                            (nth 6 this-line)
                                            (nth 7 this-line))))
        ;; We have a quad
        (progn
          (ldraw-erase-current-line)
          (ldraw-write-current-line (list (car this-line)
                                          (nth 1 this-line)
                                          
                                          (nth 2 this-line)
                                          (nth 3 this-line)
                                          (nth 4 this-line)
                                          
                                          (nth 11 this-line)
                                          (nth 12 this-line)
                                          (nth 13 this-line)

                                          (nth 8 this-line)
                                          (nth 9 this-line)
                                          (nth 10 this-line)
                                          
                                          (nth 5 this-line)
                                          (nth 6 this-line)
                                          (nth 7 this-line)))))))

(defun ldraw-bfc-reverse (&optional n)
  "Reverse the orientation of the current triangle/quadilateral.

The orientation of a triangle/quadilateral is used to determine whether
or not it will be drawn on some renderes that support BFC.  This
function is used to swap the orientation of the current triangle or
quadilateral.  It only works on line types 3 and 4."
  (interactive "P")
  (ldraw-repeat-function 'ldraw-bfc-reverse-this-line n))

(defun ldraw-comment-current-line ()
  "Comment current line if not already commented.
If the line is commented, one space is removed from the indentation to
comply with standard formatting."
  (interactive)
  (setq this-line (ldraw-parse-current-line))
  (if (and this-line
           (not (= 0 (car this-line))))
      (progn
        (beginning-of-line)
        (if (looking-at " +")
            (progn
              (re-search-forward " +")
              (backward-char 1))
          (progn
            (insert " ")
            (backward-char 1)))
        (insert "0"))))

(defun ldraw-un-comment-current-line ()
  "Uncomment current line if it starts with a \"0 [1-5]\".
If the line is uncommented, one space is added to the indentation to
comply with standard formatting."
  (interactive)
  (if (save-excursion
        (beginning-of-line)
        (looking-at " *0 +[1-5] +"))
      (save-excursion
        (beginning-of-line)
        (search-forward "0")
        (delete-char -1))))

(defun ldraw-repeat-function-over-region (fun &optional n)
  "Apply function to all lines in region."
  (interactive)
  (if (not n)
      (progn
        (setq beg (min (mark) (point)))
        (setq end (max (mark) (point)))
        (goto-char beg)
        (funcall fun)
        (while (> end (save-excursion (end-of-line) (point)))
          (next-line 1)
          (funcall fun)))
    (ldraw-repeat-function fun n)))

(defun ldraw-comment-region (&optional n)
  "Comment all lines in the region."
  (interactive "P")
  (ldraw-repeat-function-over-region 'ldraw-comment-current-line n))

(defun ldraw-un-comment-region (&optional n)
  "Uncomment all lines in the region."
  (interactive "P")
  (ldraw-repeat-function-over-region 'ldraw-un-comment-current-line n))

(defun ldraw-insert-ring-one-line (a r)
  ""
  (ldraw-insert-part-one-line (append '(1) (list colour) origin
                                      (list a) '(0 0 0)
                                      '(0) '(0 0 0)
                                      (list a) (list (concat "ring"
                                                             (number-to-string r)
                                                             ".dat")))))

(defun ldraw-insert-ring-primitive ()
  "Insert a ring primitive.
Prompt for the inner and outer radius of a ring and insert the
appropriate ring primitive if it exists.  If the cursor is on a part
line when the command is issued, the colour and origin of that part is
used for the ring primitive.

If no ring primitive is as narrow at the one the user requests,
LDraw-mode inserts the most narrow ring available, matching the
requested inner or outer radius at the user's choice.

If two overlapping rings are needed to cover the desired area,
LDraw-mode inserts them, and issues a warning that it has done so."
  (interactive)
  (require 'cl)
  (setq this-line (ldraw-parse-current-line))
  (if (and this-line
           (= (car this-line) 1))
      (progn
        (setq origin (ldraw-extract-coordinates-type-1-line this-line))
        (setq colour (car (cdr this-line))))
    (progn
      (setq origin '(0 0 0))
      (setq colour 0)))
  (setq ring-inner (float (string-to-number (read-input "Ring inner radius (LDraw Units): "))))
  (setq ring-outer (float (string-to-number (read-input "Ring outer radius (LDraw Units): "))))
  (if (>= ring-inner ring-outer)
      (error "Outer radius must be larger than inner")
    (progn
      (setq r (/ ring-inner (- ring-outer ring-inner)))
      (setq a (/ ring-inner r))
      ;; Check if r is close to an integer...
      (if (not (ldraw-significant (- r (round r))))
          (setq r (round r)))
      ;; Check if we have a ring that fits just perfectly
      (if (memq r ldraw-ring-primitives-available)
          ;; Insert the one and only ring which fits
          (ldraw-insert-ring-one-line a r)
        ;; One ring will not fit.  Do we need two, or is the space too
        ;; narrow?
        (if (> r (car (last ldraw-ring-primitives-available)))
            ;; No ring will fit -- use the narrowest one.
            ;; Does the user want to match the inner or outer radius?
            (if (y-or-n-p "No ring is as narrow as you want.  Match the outer radious?  ")
                (ldraw-insert-ring-one-line (/ ring-outer
                                               (1+ (car (last ldraw-ring-primitives-available))))
                                            (car (last ldraw-ring-primitives-available)))
              (ldraw-insert-ring-one-line (/ ring-inner
                                             (car (last ldraw-ring-primitives-available)))
                                          (car (last ldraw-ring-primitives-available))))
          ;; We need two rings to fill the space
          (progn
            (message "Inserted two partially overlapping rings to fill the space.")
            (setq r (ceiling r))
            (while (not (memq r ldraw-ring-primitives-available))
              (setq r (1+ r)))
            (ldraw-insert-ring-one-line (/ ring-outer (1+ r)) r)
            (ldraw-insert-ring-one-line (/ ring-inner r) r)))))))

(defun ldraw-jump-to-type-2-line ()
  ""
  (setq dummy next-line-add-newlines)
  (setq next-line-add-newlines nil)
  (while (or (not (ldraw-linep))
             (not (= 2 (car (ldraw-parse-current-line)))))
    (next-line 1))
  (setq next-line-add-newlines dummy))

(defun ldraw-grab-curve (curve n)
  ""
  (ldraw-jump-to-type-2-line)
  (setq line (ldraw-parse-current-line))
  (aset curve 0 (list (nth 2 line)
                      (nth 3 line)
                      (nth 4 line)))
  (aset curve 1 (list (nth 5 line)
                      (nth 6 line)
                      (nth 7 line)))
  (setq i 1)
  (next-line 1)
  (while (< i n)
    (ldraw-jump-to-type-2-line)
    (setq line (ldraw-parse-current-line))
    (setq p1 (list (nth 2 line)
                   (nth 3 line)
                   (nth 4 line)))
    (setq p2 (list (nth 5 line)
                   (nth 6 line)
                   (nth 7 line)))
    ;; Make sure the last point we recorded matches one of the
    ;; current ones...
    (if (and (ldraw-vectors-different p1 (aref curve i))
             (ldraw-vectors-different p2 (aref curve i)))
        ;; ... if not, swap the last two
        (progn
          (setq dummy (aref curve i))
          (aset curve i (aref curve (1- i)))
          (aset curve (1- i) dummy)))
    
    ;; Keep only the point which is different from the last one --
    ;; we assume the type-2 lines are connected
    (if (ldraw-vectors-different p1 (aref curve i))
        (aset curve (1+ i) p1)
      (aset curve (1+ i) p2))
    (setq i (1+ i))
    (next-line 1)))
  
(defun ldraw-fill-in-surface ()
  "Fill in a surface between two curves.

Assumes that two curves made up out of type-2 edge lines are starting at
cursor and mark position, respectively.  The curves are both assumed to
be connected and sorted in the same order.

Fills in the surface between the two curves with quadilaterals (or
triangles if needed).  Also adds type-5 conditional lines and type-2
edge lines at start and end unless both the curves are cyclic."
  (interactive)
  ;; Preserve the mark
  (setq mar (mark))
  ;; Preserve the cursor position
  (setq pos (point))
  (setq beg (min mar pos))              ; The curve starting here will be dubbed "a"
  (setq end (max mar pos))              ; The curve starting here will be dubbed "b"
  ;; What main colour?
  (setq colour (string-to-number (read-input "Colour: ")))
  ;; Count how many type-2 lines we are working with.
  (setq n 0)
  (save-excursion
    (goto-char beg)
    (while (< (save-excursion (end-of-line) (point)) end)
      (if (and (ldraw-linep)
               (= 2 (car (ldraw-parse-current-line))))
          (progn
            (setq n (1+ n))))
      (next-line 1)))
  (if (= 0 n)
      ;; Exit if no type-2 lines are present.
      (error "Found no type-2 edge lines between cursor and point")
    (progn
      ;; Grab coordinates for "a" curve.
      (goto-char beg)
      (setq curve-a (make-vector (1+ n) '(0.0 0.0 0.0)))      
      (ldraw-grab-curve curve-a n)))
  ;; Grab coordinates for "b" curve.
  (goto-char end)
  (setq curve-b (make-vector (1+ n) '(0.0 0.0 0.0)))      
  (ldraw-grab-curve curve-b n)
  ;; Preserve the edge-colour
  (setq edge-colour (nth 1 line))
  ;; If the first and last points don't match on either of the
  ;; curves, insert type-2 edge-lines.
  (if (or (ldraw-vectors-different (aref curve-a 0) (aref curve-a n))
          (ldraw-vectors-different (aref curve-b 0) (aref curve-b n)))
      (progn
        (ldraw-insert-part-one-line (append '(2) (list edge-colour)
                                            (aref curve-a 0) (aref curve-b 0)))
        (ldraw-insert-part-one-line (append '(2) (list edge-colour)
                                            (aref curve-a n) (aref curve-b n))))
    ;; If they do match on both, insert a type-5 line in stead
    (ldraw-insert-part-one-line (append '(5) (list edge-colour)
                                        (aref curve-a 0) (aref curve-b 0)
                                        (aref curve-a 1) (aref curve-a (1- n)))))
  ;; Start main recursion
  (setq i 0)
  (while (< i n)
    ;; Add type-5 conditional line only if there are more than two
    ;; vertices in the original curves.
    (if (> i 0)
        (ldraw-insert-part-one-line (append '(5) (list edge-colour)
                                            (aref curve-a i) (aref curve-b i)
                                            (aref curve-a (1- i)) (aref curve-a (1+ i)))))
    ;; Check if the four points make up a coplanar surface
    (if (> (abs (ldraw-matrix-determinant (append (ldraw-vector-subtraction (aref curve-a i) (aref curve-a (1+ i)))
                                                  (ldraw-vector-subtraction (aref curve-a i) (aref curve-b i))
                                                  (ldraw-vector-subtraction (aref curve-a i) (aref curve-b (1+ i))))))
           (* 10000 (exp (* (- ldraw-number-of-decimal-places) (log 10)))))
        (progn
          ;; Not coplanar: Split into two triangles
          (ldraw-insert-part-one-line (append '(3) (list colour)
                                              (aref curve-a i) (aref curve-a (1+ i))
                                              (aref curve-b i)))
          (ldraw-insert-part-one-line (append '(3) (list colour)
                                              (aref curve-a (1+ i)) (aref curve-b i)
                                              (aref curve-b (1+ i))))
          (ldraw-insert-part-one-line (append '(5) (list edge-colour)
                                              (aref curve-b i) (aref curve-a (1+ i))
                                              (aref curve-a i) (aref curve-b (1+ i)))))
;;;               (if (> n 1)
;;;                   (if (> i 0)
;;;                       (ldraw-insert-part-one-line (append '(5) (list edge-colour)
;;;                                                           (aref curve-b i) (aref curve-a (1+ i))
;;;                                                           (aref curve-b (1- i)) (aref curve-b (1+ i))))
;;;                     (ldraw-insert-part-one-line (append '(5) (list edge-colour)
;;;                                                         (aref curve-a (1+ i)) (aref curve-b i)
;;;                                                        (aref curve-a i) (aref curve-a (+ 2 i)))))))
      ;; Does not check for bowtie.  (Bowties should not appear as
      ;; long as the two curves have corresponding vertices.)
      (ldraw-insert-part-one-line (append '(4) (list colour)
                                          (aref curve-a i) (aref curve-a (1+ i))
                                          (aref curve-b (1+ i)) (aref curve-b i))))
    (setq i (1+ i))))

(defun ldraw-clean-current-line ()
  "Cleanup current line.
The indentation is preserved."
  ;; Preserve the cursor position
  (setq pos (point))
  ;; Parse the line
  (setq this-line (ldraw-parse-current-line))
  (ldraw-erase-current-line)
  (ldraw-write-current-line this-line)
  (goto-char pos))

(defun ldraw-translate-line (offset &optional n)
  ""
  (ldraw-repeat-function
   '(lambda () (ldraw-translate-current-line offset)) n))

(defun ldraw-translate-line-x (&optional n)
  ""
  (interactive "P")
  (setq by (read-input "X"))
  (ldraw-repeat-function
   '(lambda () (ldraw-translate-current-line (list (string-to-number by) 0 0))) n))

(defun ldraw-translate-line-y (&optional n)
  ""
  (interactive "P")
  (setq by (read-input "Y"))
  (ldraw-repeat-function
   '(lambda () (ldraw-translate-current-line (list 0 (string-to-number by) 0))) n))

(defun ldraw-translate-line-z (&optional n)
  ""
  (interactive "P")
  (setq by (read-input "Z"))
  (ldraw-repeat-function
   '(lambda () (ldraw-translate-current-line (list 0 0 (string-to-number by)))) n))

(defun ldraw-rotate-at-random-round-centre-of-part-x (&optional n)
  ""
  (setq ldraw-old-centre ldraw-turn-centre)
  (setq ldraw-turn-centre (ldraw-get-current-line-centre))
  (ldraw-rotate-line (ldraw-make-rotation-matrix
                      (list 1 0 0)
                      (random 360)))
  (setq ldraw-turn-centre ldraw-old-centre))

(defun ldraw-rotate-at-random-round-centre-of-part-y (&optional n)
  ""
  (setq ldraw-old-centre ldraw-turn-centre)
  (setq ldraw-turn-centre (ldraw-get-current-line-centre))
  (ldraw-rotate-line (ldraw-make-rotation-matrix
                      (list 0 1 0)
                      (random 360)))
  (setq ldraw-turn-centre ldraw-old-centre))

(defun ldraw-rotate-at-random-round-centre-of-part-z (&optional n)
  ""
  (setq ldraw-old-centre ldraw-turn-centre)
  (setq ldraw-turn-centre (ldraw-get-current-line-centre))
  (ldraw-rotate-line (ldraw-make-rotation-matrix
                      (list 0 0 1)
                      (random 360)))
  (setq ldraw-turn-centre ldraw-old-centre))

(defun ldraw-inline-current-line ()
  ""
  (require 'cl)
  ;; Check first if the LDraw part files are available.
  (if (file-readable-p (concat ldraw-base-dir "/"
                               (car ldraw-path)))
      (progn
        (setq this-line (ldraw-parse-current-line))
        ;; Ignore comments and non-parts
        (if (or (not this-line)
                (= (car this-line) 0)
                (> (car this-line) 1))
            (error "Not a part line; cannot be inlined")
          (setq name (car (last this-line)))
          ;; Can we find the file `name'?
          (setq found-name
                ;; Search the current directory first
                (if (setq real-name (find name (directory-files "." nil nil t)
                                          :key #'file-name-nondirectory
                                          :test #'(lambda (a b) (string-equal
                                                                 (downcase a)
                                                                 (downcase b)))))
                    (expand-file-name real-name)
                  ;; Then search the `ldraw-path'.  This search is case insensitive.
                  (car (delq nil (mapcar '(lambda (arg)
                                            (setq real-name (find name (directory-files (concat (file-name-as-directory ldraw-base-dir) arg) nil nil t)
                                                                  :key #'file-name-nondirectory
                                                                  :test #'(lambda (a b) (string-equal (downcase a) (downcase b)))))
                                            (if real-name
                                                (concat (file-name-as-directory (concat (file-name-as-directory ldraw-base-dir) arg)) real-name)))
                                         ldraw-path)))))
          (if (not found-name)
              ;; Sorry, couldn't find the part; return.
              (error (concat "Couldn't find file: " name))
            (beginning-of-line)
            (setq old-line-indent (buffer-substring-no-properties (point) (progn (skip-chars-forward "\t ") (point))))
            (kill-region (point) (progn (end-of-line) (point)))
            (insert "0 Inline (")
            (ldraw-write-current-line this-line)
            (insert ")
")
            (setq ldraw-buffer (current-buffer))
            (set-buffer (get-buffer-create " *ldraw-inline*"))
            (ldraw-make-syntax-table)
            (erase-buffer)
            (insert-file-contents found-name)
            (beginning-of-buffer)
            (setq old-centre ldraw-turn-centre)
            (setq ldraw-turn-centre '(0 0 0))
            (setq offset (list (nth 2 this-line)
                               (nth 3 this-line)
                               (nth 4 this-line)))
            (setq m (list (nth 5 this-line)
                          (nth 6 this-line)
                          (nth 7 this-line)
                          (nth 8 this-line)
                          (nth 9 this-line)
                          (nth 10 this-line)
                          (nth 11 this-line)
                          (nth 12 this-line)
                          (nth 13 this-line)))
;;; Note that this way of doing the inlining is very inefficient.  It
;;; should be reprogrammed to not actually perform the changes in the
;;; work buffer, but in stead change and transfer each line
;;; individually.
            ;; Rotate the part appropriately
            (ldraw-rotate-line m '(4))
            ;; Then translate it
            (ldraw-translate-line offset '(4))
            ;; Check for any occurrences of the colour 16 and 24, unless the
            ;; inlined part already has colour 16
            (if (and (> (car this-line) 0)
                     (not (= (nth 1 this-line) 16)))
                (ldraw-repeat-function
                 '(lambda ()
                    (setq check-line (ldraw-parse-current-line))
                    (if (and (or (not check-line)
                                 (> (car check-line) 0))
                             (= (nth 1 check-line) 16))
                        ;; We have colour 16, so exchange with the proper colour
                        (progn
                          (ldraw-erase-current-line)
                          (ldraw-write-current-line (append (list (nth 0 check-line)
                                                                  (nth 1 this-line))
                                                            (cdr (cdr check-line))))))
                    (if (and (or (not check-line)
                                 (> (car check-line) 0))
                             (= (nth 1 check-line) 24))
                        ;; We have colour 24, so exchange with the edge colour
                        ;; associated with the original part's colour
                        (progn
                          (ldraw-erase-current-line)
                          (ldraw-write-current-line
                           (append (list (nth 0 check-line)
                                         (nth (% (nth 1 this-line) 16)
                                              ldraw-edge-colour-table))
                                   (cdr (cdr check-line)))))))
                 '(4)))
            ;; NOTE: If the inlined part has colour 24, all the colours of the
            ;; inlined parts should probably be complemented.  This is not
            ;; done.
      
            ;; Copy the parts from the work buffer into the current buffer
            (ldraw-repeat-function
             '(lambda ()
                (setq this-line-indent
                      (buffer-substring (progn (beginning-of-line) (point))
                                        (progn (skip-chars-forward "\t ") (point))))
                (setq copy-line (ldraw-parse-current-line))
                (if copy-line
                    (progn
                      (set-buffer ldraw-buffer)
                      (beginning-of-line)
                      (insert (concat old-line-indent ldraw-inline-indent this-line-indent))
                      (ldraw-write-current-line copy-line)
                      (insert "
")
                      (set-buffer (get-buffer " *ldraw-inline*"))))) '(4))
            (set-buffer ldraw-buffer)
            (insert (concat old-line-indent "0 End Inline"))
            (beginning-of-line)
            (setq ldraw-turn-centre old-centre))))
    (error (concat "Could not find the directory "
                   (concat ldraw-base-dir "/" (car ldraw-path))
                   "  Are you sure you've installed the LDraw parts library at "
                   ldraw-base-dir "?"))))

(defun ldraw-inline-line (&optional n)
  "Inline part on line(s).

This command can easily be applied to many lines in the model file by
giving a prefix argument.  An empty prefix argument means apply to all
lines, a positive argument n to the n following lines and a negative
argument -n to the n preceding lines.

Prepends the inlined section with `ldraw-inline-indent' to visualize
different layers of indentation.

The current directory is searched first for part files to inline, then
the directories in the list `ldraw-path' relative to `ldraw-base-dir'.

When encoutering the special colour 24 in a part to be inlined, this is
substituted according to the table `ldraw-edge-colour-table'."
  (interactive "P")
  (ldraw-repeat-function 'ldraw-inline-current-line n))

(defun ldraw-clean-line (&optional n)
  "Clean up line(s).

This command can easily be applied to many lines in the model file by
giving a prefix argument.  An empty prefix argument means apply to all
lines, a positive argument n to the n following lines and a negative
argument -n to the n preceding lines.

Calling `ldraw-clean-line' with no prefix argument cleans the current
line.  This preserves the indentation, but wipes away all surplus
whitespace thereafter.  Further, it rounds all numbers to
`ldraw-number-of-decimal-places' number of decimals."
  (interactive "P")
  (ldraw-repeat-function 'ldraw-clean-current-line n))

(defun ldraw-change-colour-current-line (colour &optional n)
  ""
  (setq line (ldraw-parse-current-line))
  (if (or (not line)
          (> (car line) 0))
      ;; This is indeed a line which has a colour associated, so change
      ;; it.
      (progn
        (ldraw-erase-current-line)
        (ldraw-write-current-line (append (list (car line)
                                                colour)
                                          (nthcdr 2 line))))))


(defun ldraw-change-colour-line (&optional n)
  "Prompt for a new colour for line(s)."
  (interactive "P")
  (setq colour (string-to-number (read-string "Colour:")))
  (ldraw-repeat-function '(lambda () (ldraw-change-colour-current-line colour)) n))

(defun ldraw-rotate-line (m &optional n)
  ""
  (ldraw-repeat-function '(lambda () (ldraw-rotate-current-line m)) n))

(defun ldraw-rotate-line-reverse (m &optional n)
  ""
  (ldraw-repeat-function '(lambda () (ldraw-rotate-current-line-reverse m)) n))

(defun ldraw-turn-line (&optional n)
  "Rotates line(s).

This command can easily be applied to many lines in the model file by
giving a prefix argument.  An empty prefix argument means apply to all
lines, a positive argument n to the n following lines and a negative
argument -n to the n preceding lines.

Prompts for axis to rotate around and an angle.  Rotates around
`ldraw-turn-centre'."
  (interactive "P")
  (setq dir (read-char "X-axis Y-axis Z-axis Centre-Set"))
  (cond ((or (= dir ?x) (= dir ?X))
         (ldraw-rotate-line (ldraw-make-rotation-matrix
                             (list 1 0 0)
                             (ldraw-prompt-angle "X-angle:")) n))
        ((or (= dir ?y) (= dir ?Y))
         (ldraw-rotate-line (ldraw-make-rotation-matrix
                             (list 0 1 0)
                             (ldraw-prompt-angle "Y-angle:")) n))
        ((or (= dir ?z) (= dir ?Z))
         (ldraw-rotate-line (ldraw-make-rotation-matrix
                             (list 0 0 1)
                             (ldraw-prompt-angle "Z-angle:")) n))
        ((or (= dir ?c) (= dir ?C))
         (setq ldraw-turn-centre (ldraw-get-current-line-centre)))))

(defun ldraw-rotate-at-random-round-centre-of-part (&optional n)
  "Rotate a line at random around a given axis."
  (interactive "P")
  (setq dir (read-char "X-axis Y-axis Z-axis"))
  (cond ((or (= dir ?x) (= dir ?X))
         (ldraw-repeat-function
          '(lambda () (ldraw-rotate-at-random-round-centre-of-part-x)) n))
        ((or (= dir ?y) (= dir ?Y))
         (ldraw-repeat-function
          '(lambda () (ldraw-rotate-at-random-round-centre-of-part-x)) n))
        ((or (= dir ?z) (= dir ?Z))
         (ldraw-repeat-function
          '(lambda () (ldraw-rotate-at-random-round-centre-of-part-x)) n))))

(defun ldraw-move-line (&optional n)
  "Moves line(s).

This command can easily be applied to many lines in the model file by
giving a prefix argument.  An empty prefix argument means apply to all
lines, a positive argument n to the n following lines and a negative
argument -n to the n preceding lines.

Prompts for an axis to move along and a number, which is the offset."
  (interactive "P")
  (setq dir (read-char "X-axis Y-axis Z-axis"))
  (cond ((or (= dir ?x) (= dir ?X))
         (ldraw-translate-line-x n))
        ((or (= dir ?y) (= dir ?Y))
         (ldraw-translate-line-y n))
        ((or (= dir ?z) (= dir ?Z))
         (ldraw-translate-line-z n))))

(defun ldraw-check-for-identical-vertices-six-coordinates (coordinates)
  (and (= (nth 0 coordinates) (nth 3 coordinates))
       (= (nth 1 coordinates) (nth 4 coordinates))
       (= (nth 2 coordinates) (nth 5 coordinates))))

(defun ldraw-check-for-identical-vertices-current-line ()
  (interactive)
  (setq this-line (ldraw-parse-current-line))
  (if (not (or (not this-line)
               (or (= (car this-line) 0)
                   (= (car this-line) 1))))
      (cond ((= (car this-line) 2)      ; Line
             (if (ldraw-check-for-identical-vertices-six-coordinates
                  (nthcdr 2 this-line))
                 (ldraw-blank-out-current-line)))
            ((= (car this-line) 3)      ; Triangle
             (setq x1 (nth 2 this-line)
                   y1 (nth 3 this-line)
                   z1 (nth 4 this-line)
                   x2 (nth 5 this-line)
                   y2 (nth 6 this-line)
                   z2 (nth 7 this-line)
                   x3 (nth 8 this-line)
                   y3 (nth 9 this-line)
                   z3 (nth 10 this-line))
             (if (or (ldraw-check-for-identical-vertices-six-coordinates
                      (list x1 y1 z1 x2 y2 z2))
                     (ldraw-check-for-identical-vertices-six-coordinates
                      (list x1 y1 z1 x3 y3 z3))
                     (ldraw-check-for-identical-vertices-six-coordinates
                      (list x2 y2 z2 x3 y3 z3)))
                 (ldraw-blank-out-current-line)))
            ((= (car this-line) 4)      ; Quad
             (setq x1 (nth 2 this-line)
                   y1 (nth 3 this-line)
                   z1 (nth 4 this-line)
                   x2 (nth 5 this-line)
                   y2 (nth 6 this-line)
                   z2 (nth 7 this-line)
                   x3 (nth 8 this-line)
                   y3 (nth 9 this-line)
                   z3 (nth 10 this-line)
                   x4 (nth 11 this-line)
                   y4 (nth 12 this-line)
                   z4 (nth 13 this-line))
             (if (or (and (ldraw-check-for-identical-vertices-six-coordinates
                           (list x1 y1 z1 x2 y2 z2))
                          (ldraw-check-for-identical-vertices-six-coordinates
                           (list x3 y3 z3 x4 y4 z4)))
                     (and (ldraw-check-for-identical-vertices-six-coordinates
                           (list x2 y2 z2 x3 y3 z3))
                          (ldraw-check-for-identical-vertices-six-coordinates
                           (list x4 y4 z4 x1 y1 z1)))
                     (and (ldraw-check-for-identical-vertices-six-coordinates
                           (list x2 y2 z2 x4 y4 z4))
                          (ldraw-check-for-identical-vertices-six-coordinates
                           (list x3 y3 z3 x1 y1 z1))))
                 (ldraw-blank-out-current-line)))
            ((= (car this-line) 5)      ; Conditional
             (setq x1 (nth 2 this-line)
                   y1 (nth 3 this-line)
                   z1 (nth 4 this-line)
                   x2 (nth 5 this-line)
                   y2 (nth 6 this-line)
                   z2 (nth 7 this-line))
             (if (ldraw-check-for-identical-vertices-six-coordinates
                  (list x1 y1 z1 x2 y2 z2))
                 (ldraw-blank-out-current-line))))))

(defun ldraw-check-for-identical-vertices (&optional n)
  ""
  (interactive "P")
  (ldraw-repeat-function 'ldraw-check-for-identical-vertices-current-line n))

(defun ldraw-distance-euclidian (p1 p2)
  "Find the euclidian distance between two points."
  (sqrt (+ (expt (- (car p1) (car p2)) 2)
           (expt (- (car (cdr p1)) (car (cdr p2))) 2)
           (expt (- (car (cdr (cdr p1))) (car (cdr (cdr p2)))) 2))))

(defun ldraw-coordinate-multiplication (s p)
  ""
  (list (* s (car p))
        (* s (car (cdr p)))
        (* s (car (cdr (cdr p))))))

(defun ldraw-coordinate-sum (p1 p2)
  ""
  (list (+ (car p1) (car p2))
        (+ (car (cdr p1)) (car (cdr p2)))
        (+ (car (cdr (cdr p1))) (car (cdr (cdr p2))))))

(defun bezier-basis-0 (u) "" (expt (- 1 u) 3))
(defun bezier-basis-1 (u) "" (* 3 u (expt (- 1 u) 2)))
(defun bezier-basis-2 (u) "" (* 3 (expt u 2) (- 1 u)))
(defun bezier-basis-3 (u) "" (expt u 3))

(defun bezier-sum (u p0 p1 p2 p3)
  ""
  (ldraw-coordinate-sum (ldraw-coordinate-sum
                         (ldraw-coordinate-multiplication (bezier-basis-0 u) p0)
                         (ldraw-coordinate-multiplication (bezier-basis-1 u) p1))
                        (ldraw-coordinate-sum
                         (ldraw-coordinate-multiplication (bezier-basis-2 u) p2)
                         (ldraw-coordinate-multiplication (bezier-basis-3 u) p3))))
                        
(defun ldraw-insert-bezier-curve ()
  "This is a command to insert Bézier curves in your model file.

There are two main ways to use this function.

Use predefined hoses:

Right now, this function can be used to insert some kinds of hoses
automatically.  These are the `73590B.DAT Hose Flexible 8.5L with
Tabs', `73590A.DAT Hose Flexible 8.5L without Tabs', the Flexible
Technic Axles, the Technic Flex-System Hoses and the Ribbed Technic
Hoses.

To compose a hose of the first kind, simply insert the end points
`750.DAT Hose Flexible End 1 x 1 x 2/3 with Tabs' or `752.DAT Hose
Flexible End 1 x 1 x 2/3 without Tabs' depending on the type of hose
you want.  When you have inserted a pair of these end points,
LDraw-mode know where you want the hose to start and end, as well as
the initial angle of the hose at the end points.  To finalize the
hose, simply invoke this command with the cursor on either of the end
points.  That's all!

To compose a bent Flexible Technic Axle, insert the skinny end parts
where you want them, eg:

    1 16 -90 40 0 0 5 0 -1 0 0 0 0 1 STUD3A.DAT
    1 16 20 0 -90 0 0 1 1 0 0 0 5 0 STUD3A.DAT

Place the cursor on either of the lines and invoke the function.  You
will be prompted for the length of the bent portion of the axle,
ie. the portion of the axle between the skinny end parts.  If the axle
you want to model has a total length of 11 LEGO units, say, you would
respond 180 to get the correct length.  Note that 180 LDraw units
equals 9 LEGO units.  Add to this the length of the end parts (1 unit
each) and you have a total length of 11 LEGO units.

To insert a Technic Flex-System Hose, you will need to specify the
position of the end parts.  Then press C-c C-b and be prompted for the
length of the hose segment to insert.

If you want a Ribbed Technic Hose, simply insert the end segments
where you want them.  Hit C-c C-b, which will prompt you for the
number of notches to insert.  Count the number of notches on the hose
you want to model and subtract two for the end segments.


Make your own hoses: The second option is to take full control yourself
over the hose creation process.  This way, you can make virtually any
kinds of flexible hose.  The rest of this documentation is devoted to
this method.

This is done by writing four subsequent part lines, leaving the cursor
on the first of these, and executing this command.

The only information used from the four part lines is the colour of
the first part, which will be used as the colour of the curve segments,
and the position of the parts.  The position of the first and fourth
parts are used as end points, while the position of the second and third
are the control points.  I'll tell you more about each of these points
later on.

When you execute this command, you are prompted for the total length of
the flexible hose in LDraw units.  Keep in mind that one 2×4 brick is 40
by 80 LDraw units, and stretch the hose out next to a long plate to
measure the length of it.

It is obvious that a curved hose cannot be modeled directly in LDraw.
We need to split it up in many small, straight portions to achieve the
look of a curved one.  The individual straight portions may be long or
short, in the latter case you'll need many of them.  The total number of
segments is the next information the program will promt you for.  Keep
in mind that with a l long hose split into n segments, each of the
segments must have the length l/n.  If the curvature is high, you may
want to make each segment a little bit longer than l/n to avoid holes in
the outer half of the curve where the segments meet.

The program will also prompt you for the file to use as one segment.
One segment must be centered in the origin, and have a height of l/n (or
a little bit more, remember the discussion in the previous paragraph).
That is to say, the individual segments must have the lower bound at
y=l/2n and the upper bound at y=-l/2n.

If you are familiar with Bézier curves, you will know that the end
points and two control points will fully determine the shape of the
curve.  So why were you prompted with the length of the curve above?
Well, you most likely have a hose of a given length which you will want
to model.  Simply stating the end and control points to model this is
very difficult, as it is almost impossible to find the length of a given
Bézier curve.  Sure, the curve can be drawn, so it's length can also be
measured, but you will need to use numerical integration to do so.  Most
likely, you will want the computer to do this job for you.

So the control points you stated above are not definite.  LDraw-mode
will move the first control point forward and backward along the line
composed from the first end point, and similar with the second, to
achieve the length you specified.  But the ratio of the distance from
the first control point to the first end point and the second control
point to the second end point is preserved.  So by specifying the
control points, you are really only specifying the angle of the curve at
the end points (the curve's tangent at the first end point will point at
the first control point and ditto for the second) and which of the ends
that will curve most (the ratio of the distances).  If the distance
between the first end and control point is the larger, the effect of the
hose being less flexible in that end is simulated.  This is probably
only rarely needed, so you'll usually want the ration to be one.

Some variables control how the numerical integration works.  The
parameter `ldraw-bezier-integration-points-per-segment' is
the number of points to insert between every segment to calculate the
total length of the curve.  Eight is the default, which is probably more
than enough unless you have few segments and much curvature.

The variable `ldraw-bezier-integration-epsilon' is the highest deviation
from the length you specified that you can accept.  If you're modeling a
very short curve, you may want to lower this number.

`ldraw-bezier-integration-max-iterations' specifies the total number of
iterations you can tolerate.  If the length of the curve LDraw mode
comes up with is too short or too long compared with what you originally
wanted, you can try to increase this number to overcome the problem.
(Another solution to this problem is to alter the distance between the
control points and the end points.  If the curve LDraw-mode fits is too
short, try to increase this distance, keeping the ratio constant, and
vice versa.)

`ldraw-bezier-rotate-vector' is a vector which defaults to the unit y
vector.  The first axis in the rotated coordinate system should be
perpendicular to this vector.  Try to alter this vector if you
experience weird twisting of the curve.  In general, avoid a vector
which is close in direction to the curve at any point to avoid this
twisting.

In case you need the control points LDraw-mode calculated by numerical
integration, these are included as a comment in the file.  If you want
to duplicate the curve in a different 3D program, e.g., POV-Ray, using
these coordinates should suffice.

You may also want to visualize the control points yourself in the .DAT
code.  Setting the `ldraw-bezier-draw-control-lines' variable to t
adds two extra type-2 lines to the buffer.  The first one is a line
from the starting point to the first control point, while the second
is a line from the end point to the second control point.  This
feature is disabled by default."

  (interactive)
  (if (save-excursion
        (setq this-line (ldraw-parse-current-line))
        (and this-line
           (= 1 (car this-line))
           (member (upcase (file-name-sans-extension (car (last this-line))))
                   '("750" "752" "STUD3A" "76" "79" "5306" "TUBE-END" "X342"))))
      ;; Yes, we have a hose we recognize
      (progn
       (setq end-part (car (last this-line)))
       ;; Find the other end.  It could be on the next or previous line.
       (if (save-excursion
              (forward-line -1)
              (string= end-part (car (last (ldraw-parse-current-line)))))
           (forward-line -1)
          (if (not (save-excursion
                      (forward-line 1)
                      (string= end-part (car (last (ldraw-parse-current-line))))))
             (error (concat "Could not find an end point matching the part "
                            end-part))))
       (if (member (file-name-sans-extension end-part) '("750" "752"))
       ;; We have a hose of the type `73590B.DAT Hose Flexible 8.5L with
       ;; Tabs' or `73590A.DAT Hose Flexible 8.5L without Tabs'
       ;;
       ;; Start by inserting extra parts we need.
       (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (ldraw-insert-part-one-line
        (ldraw-rotate (nconc (delq (car (last line-1)) line-1) '("755.dat"))
                      (ldraw-make-rotation-matrix (list 1 0 0) 180) t))
       (ldraw-insert-part-one-line
        (ldraw-rotate (nconc (delq (car (last line-2)) line-2) '("755.dat"))
                      (ldraw-make-rotation-matrix (list 1 0 0) 180) t))
       (forward-line 1)
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -5  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -5  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -15  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -15  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length 130
             bezier-segments 50
             bezier-element "754.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       ;; Lower all the parts by 1 LDU
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
          (setq this-line (ldraw-parse-current-line))
          (ldraw-erase-current-line)
          (ldraw-write-current-line
             (ldraw-rotate-line-matrix4 this-line
                  (list 1 0 0 0  0 1 0 1.0  0 0 1 0  0 0 0 1) t))
          (forward-line 1))
       (forward-line -1)
       ;; Substitute the last element with 756.dat
       (setq this-line (ldraw-parse-current-line))
       (ldraw-erase-current-line)
       (ldraw-write-current-line (nconc (delq (car (last this-line)) this-line) '("756.dat"))))
  ;; Finished inserting the type `73590B.DAT Hose Flexible 8.5L with
  ;; Tabs' or `73590A.DAT Hose Flexible 8.5L without Tabs'

  (if (string= (upcase (file-name-sans-extension end-part)) "STUD3A")
    ;; We have a hose of the kind `Technic Axle Flexible'
       (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length (string-to-number (read-input
             "Total length of axle element to insert (LDraw Units): ")))
       (setq bezier-segments (floor bezier-length 4)
             bezier-element "axlehol8.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
          (if (> (min (abs (- 1 i)) (abs (- bezier-segments i))) 4)
             (progn
             ;; Lower all the parts by 1 LDU
             (setq this-line (ldraw-parse-current-line))
             (ldraw-erase-current-line)
             (ldraw-write-current-line
               (ldraw-rotate-line-matrix4 this-line
                    (list 1 0 0 0  0 4.26 0 -2.13  0 0 1 0  0 0 0 1) t))))
          (if (< i 6)
             (progn
               (setq this-line (ldraw-parse-current-line))
               (ldraw-erase-current-line)
               (ldraw-write-current-line
                  (nconc (delq (car (last this-line))
                       (ldraw-rotate-line-matrix4 this-line
                           (list 0 -1 0 0  1 0 0 -2  0 0 1 0  0 0 0 1) t))
                       (list (concat "s\\faxle" (number-to-string i) ".dat"))))))
          (if (> i (- bezier-segments 5))
             (progn
               (setq this-line (ldraw-parse-current-line))
               (ldraw-erase-current-line)
               (ldraw-write-current-line
                  (nconc (delq (car (last this-line))
                       (ldraw-rotate-line-matrix4 this-line
                           (list 0 1 0 0  -1 0 0 2  0 0 1 0  0 0 0 1) t))
                       (list (concat "s\\faxle" (number-to-string (1+ (- bezier-segments i))) ".dat"))))))
          (forward-line 1))
       (forward-line -1))
          (if (string= (upcase (file-name-sans-extension end-part)) "76")
            ;; We have a hose of the kind `Technic Flex-System Hose'
            (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length (string-to-number (read-input
             "Total length of hose to insert (LDraw Units): ")))
       (setq bezier-segments (floor bezier-length 4)
             bezier-element "77.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
             (setq this-line (ldraw-parse-current-line))
             (ldraw-erase-current-line)
             (ldraw-write-current-line
               (ldraw-rotate-line-matrix4 this-line
                    (list 1 0 0 0  0 4.4 0 -2.2  0 0 1 0  0 0 0 1) t))
          (forward-line 1))
       (forward-line -1)
               )
          (if (string= (upcase (file-name-sans-extension end-part)) "TUBE-END")
            ;; We have a hose of the kind `Technic Pneumatic Tube'
            (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length (string-to-number (read-input
             "Total length of hose to insert (LDraw Units): ")))
       (setq bezier-segments (floor bezier-length 4)
             bezier-element "TUBE-SEG.DAT"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
             (setq this-line (ldraw-parse-current-line))
             (ldraw-erase-current-line)
             (ldraw-write-current-line
               (ldraw-rotate-line-matrix4 this-line
                    (list 1 0 0 0  0 4.6 0 -2.3  0 0 1 0  0 0 0 1) t))
          (forward-line 1))
       (forward-line -1))
          (if (string= (upcase (file-name-sans-extension end-part)) "79")
            ;; We have a hose of the kind `Technic Ribbed Hose'

      (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -3.2  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -3.2  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -10  0 0 1 0  0 0 0 1) t)))
       (setq bezier-segments (string-to-number (read-input
             "Number of segments (notches) to include: ")))
       (setq bezier-length (* bezier-segments 6.2)
             bezier-element "80.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1))
;; End of notched hose


          (if (string= (upcase (file-name-sans-extension end-part)) "5306")
            ;; We have an electric brick with wire end 

      (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 40  0 1 0 5.25  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 40  0 1 0 5.25  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 50  0 1 0 5.25  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 50  0 1 0 5.25  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length (string-to-number (read-input
             "Length of wire to insert (LDU): ")))
       (setq bezier-segments bezier-length
             bezier-element "5306s01.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
             (setq this-line (ldraw-parse-current-line))
             (ldraw-erase-current-line)
             (ldraw-write-current-line
               (ldraw-rotate-line-matrix4 this-line
                    (list 0 0 1 0  1.1 0 0 0  0 1 0 0  0 0 0 1) t))
          (forward-line 1))
       (forward-line -1)
       (search-backward "Bezier")
       (forward-line 1))

;; End of electrical wire

          (if (string= (upcase (file-name-sans-extension end-part)) "X342")
            ;; We have a hose of the kind `Technic Flex-System Cable'
            (progn
       (setq line-1 (ldraw-parse-current-line))
       (forward-line 1)
       (setq line-2 (ldraw-parse-current-line))
       (setq bezier-start (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -20  0 0 1 0  0 0 0 1) t)))
       (setq bezier-end (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -20  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-1 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -30  0 0 1 0  0 0 0 1) t)))
       (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line
             (ldraw-rotate-line-matrix4
             (append line-2 (list "dummy.dat"))
             (list 1 0 0 0  0 1 0 -30  0 0 1 0  0 0 0 1) t)))
       (setq bezier-length (string-to-number (read-input
             "Total length of wire to insert (LDraw Units): ")))
       (setq bezier-segments (floor bezier-length 2)
             bezier-element "x343.dat"
             bezier-colour (car (cdr line-1)))
       (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
           (error "Distance between start and end points longer than curve length"))
       (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
       (search-backward "Bezier")
       (forward-line 1)
       (setq i 0)
       (while (< i bezier-segments)
          (setq i (1+ i))
             (setq this-line (ldraw-parse-current-line))
             (ldraw-erase-current-line)
             (ldraw-write-current-line
               (ldraw-rotate-line-matrix4 this-line
                    (list 1 0 0 0  0 2.2 0 -1.1  0 0 1 0  0 0 0 1) t))
          (forward-line 1))
       (forward-line -1))

            ;; End of `Technic Flex-System Cable'

))))))))

  ;; We try to do an advanced Bézier curve, rather than the simplyfied one.
  (setq bezier-length (string-to-number (read-input "Total length (LDraw Units): ")))
  (setq bezier-segments (string-to-number (read-input "Number of segments: ")))
  (setq bezier-element (read-input "File to use as segment: "))
  ;; Check that we have a ".DAT" extension.  Does not work for Emacs 19.
  (if (> emacs-major-version 19)
      (if (or (not (file-name-extension bezier-element))
              (not (string= (upcase (file-name-extension bezier-element)) "DAT")))
          (setq bezier-element (concat bezier-element ".DAT"))))
  (setq bezier-region-start (progn (beginning-of-line) (point)))
  (setq bezier-region-end (save-excursion (setq bezier-start (ldraw-extract-coordinates-type-1-line (ldraw-parse-current-line)))
                                          (setq bezier-colour (car (cdr (ldraw-parse-current-line))))
                                          (forward-line 1)
                                          (setq bezier-control-1 (ldraw-extract-coordinates-type-1-line (ldraw-parse-current-line)))
                                          (forward-line 1)
                                          (setq bezier-control-2 (ldraw-extract-coordinates-type-1-line (ldraw-parse-current-line)))
                                          (forward-line 1)
                                          (setq bezier-end (ldraw-extract-coordinates-type-1-line (ldraw-parse-current-line)))
                                          (beginning-of-line)
                                          (forward-line 1)
                                          (point)))
  ;; Verify that we are not trying to fit a curve which is too short
  (if (> (ldraw-distance-euclidian bezier-start bezier-end) bezier-length)
      (error "Distance between start and end points longer than curve length")
    (kill-region bezier-region-start bezier-region-end)
  (ldraw-insert-bezier-curve-do-it bezier-length bezier-segments
                                   bezier-element bezier-colour
                                   bezier-start bezier-control-1
                                   bezier-control-2 bezier-end))))

(defun ldraw-insert-bezier-curve-do-it (bezier-length bezier-segments
                                        bezier-element bezier-colour
                                        bezier-start bezier-control-1
                                        bezier-control-2 bezier-end)
    ;; Start optimization to find the correct length
    (setq bezier-integration-lengths (make-vector (* bezier-segments ldraw-bezier-integration-points-per-segment) 0.0))
    (setq bezier-integration-pos (make-vector (* bezier-segments ldraw-bezier-integration-points-per-segment) 0.0))
    (setq factor 1.0)
    (setq distance 0.5)
    (setq last 1)
    (setq iterations 0)
    (setq length 0.0)
    (while (and (< iterations ldraw-bezier-integration-max-iterations)
                (> (abs (- length bezier-length)) ldraw-bezier-integration-epsilon))
      (progn
        (setq count 0)
        (setq length 0.0)
        (setq bezier-last-pos bezier-start)
        (setq bezier-c1 (ldraw-coordinate-sum bezier-start (ldraw-coordinate-multiplication factor (ldraw-coordinate-sum (ldraw-coordinate-multiplication -1.0 bezier-start) bezier-control-1))))
        (setq bezier-c2 (ldraw-coordinate-sum bezier-end (ldraw-coordinate-multiplication factor (ldraw-coordinate-sum (ldraw-coordinate-multiplication -1.0 bezier-end) bezier-control-2))))
        (while (< count (* bezier-segments ldraw-bezier-integration-points-per-segment))
          (progn
            (aset bezier-integration-pos count (bezier-sum (/ (float count) bezier-segments ldraw-bezier-integration-points-per-segment)
                                                           bezier-start
                                                           bezier-c1
                                                           bezier-c2
                                                           bezier-end))
            (setq length (+ length (ldraw-distance-euclidian (aref bezier-integration-pos count) bezier-last-pos)))
            (aset bezier-integration-lengths count length)
            (setq bezier-last-pos (aref bezier-integration-pos count))
            
            (setq count (1+ count)))) 
    (if (< length bezier-length)
        (progn
          (setq factor (+ factor distance))
          (if (= last 0) (setq distance (/ distance 2))
            (setq distance (* distance 1.4)))
          
          (setq last 1))
      (progn
        (setq factor (- factor distance))
        (if (= last 1) (setq distance (/ distance 2)))
        (setq last 0)))
    (setq iterations (1+ iterations))))
    (message (concat "Please wait, fitting control points, iteration=" (number-to-string iterations) "  length=" (number-to-string length)))
    ;; Finished fitting
    (message (concat "Done fitting control points, total length=" (number-to-string length)))
    (forward-line -1)
    (if ldraw-bezier-draw-control-lines
        (progn
          (ldraw-insert-part-one-line (list 0 "The following two lines are for illustrative purposes only."))
          (ldraw-insert-part-one-line (append (list 2 bezier-colour) bezier-start bezier-c1))
          (ldraw-insert-part-one-line (append (list 2 bezier-colour) bezier-end bezier-c2))))
    (ldraw-insert-part-one-line (append (list 0 "Bezier, n=" bezier-segments "l=" length)
                                        (list "(")
                                        bezier-start 
                                        '(") (")
                                        bezier-c1
                                        '(") (")
                                        bezier-c2 
                                        '(") (")
                                        bezier-end 
                                        '(")")))
    (setq count 0)
    (setq bezier-i-last 0.0)
    (setq bezier-search 0)
    (while (< count bezier-segments)
      (progn
        (if (= count (1- bezier-segments))
            (setq bezier-i 1.0)
          (progn
            (while (and (< bezier-search
                           (* bezier-segments
                              ldraw-bezier-integration-points-per-segment))
                        (< (aref bezier-integration-lengths bezier-search)
                           (/ (* length (float (1+ count))) bezier-segments)))
              (setq bezier-search (1+ bezier-search)))
            ;; Interpolate to find the pos of the segment
            (setq i (/ (- (* length (/ (float (1+ count)) bezier-segments))
                          (aref bezier-integration-lengths (1- bezier-search))) 
                       (- (aref bezier-integration-lengths bezier-search)
                          (aref bezier-integration-lengths (1- bezier-search)))))
            (setq bezier-i (/ (+ (float (1- bezier-search)) i)
                              bezier-segments
                              ldraw-bezier-integration-points-per-segment))))
;(message (concat " " (number-to-string (aref bezier-integration-lengths (1- bezier-search)))
;                 " " (number-to-string (aref bezier-integration-lengths bezier-search))
;                 " " (number-to-string (/ (* length (float (1+ count))) bezier-segments))
;                 " " (number-to-string i)
;                 " " (number-to-string bezier-i)))
        (ldraw-insert-part-one-line (append (list 1 bezier-colour) 
                                            (ldraw-coordinate-multiplication 0.5 (ldraw-coordinate-sum (bezier-sum bezier-i-last bezier-start bezier-c1 bezier-c2 bezier-end) (bezier-sum bezier-i bezier-start bezier-c1 bezier-c2 bezier-end)))
                                          (ldraw-rotation-matrix (ldraw-coordinate-sum (bezier-sum bezier-i-last bezier-start bezier-c1 bezier-c2 bezier-end) (ldraw-coordinate-multiplication -1.0 (bezier-sum bezier-i bezier-start bezier-c1 bezier-c2 bezier-end))))
                                          (list bezier-element)))

        (setq bezier-i-last bezier-i)
        (setq count (1+ count)))))



(defun ldraw-enter-search-buffer ()
  "Enter a buffer with the contents of the parts.lst file.

When entering this buffer, you can use Emacs' usual tools to search for
a given part.  Press ENTER to select a part.  If the line currently
being edited was a part line, the selected part is substituted for the
original one.  The name of the part is also inserted into the
kill-ring."
  (interactive)
  (setq old-window-configuration (current-window-configuration))
  (setq search-buffer (get-buffer-create "*LDraw-search-buffer*"))
  (switch-to-buffer-other-window search-buffer t)
  (if (= (buffer-size) 0)
      (progn
        (insert-file-contents (concat (file-name-as-directory ldraw-base-dir)
                                      ldraw-parts-lst-file-name))
        (toggle-read-only 1)
        (beginning-of-buffer)
        (use-local-map ldraw-search-mode-map)
        ))
  (message "ENTER to select a part, DELETE to exit or C-c C-p to view a part."))
  
(defun ldraw-search-fetch-part-image-from-web ()
  ""
  (interactive)
  (ldraw-fetch-a-part-image-from-web (save-excursion (buffer-substring-no-properties
                                                      (progn (beginning-of-line)
                                                             (point))
                                                      (progn (beginning-of-line)
                                                             (search-forward ".")
                                                             (backward-char)
                                                             (point)))) 7))

(defun ldraw-search-select-part ()
  ""
  (interactive)
  (setq name (save-excursion (buffer-substring-no-properties
                              (progn (beginning-of-line)
                                     (point))
                              (progn (beginning-of-line)
                                     (search-forward " ")
                                     (backward-char)
                                     (point)))))
  (kill-ring-save (save-excursion (beginning-of-line)
                                  (point))
                  (save-excursion (beginning-of-line)
                                  (search-forward " ")
                                  (backward-char)
                                  (point)))
  (set-window-configuration old-window-configuration)
  (ldraw-new-part-name name))

(defun ldraw-search-exit ()
  ""
  (interactive)
  (set-window-configuration old-window-configuration)
)

(defun ldraw-insert-headers ()
  "Insert headers in LDraw file.

If this is an empty file, insert standard headers and leave the point
where one would normally type the name of the part.  If the file is not
empty, don't touch it."
  (if (= 0 (buffer-size))
      (progn
        (insert (concat "0 
0 Name: " (file-name-nondirectory (car file-name-history)) "

 1 16 0 0 0 1 0 0 0 1 0 0 0 1 3001.DAT
0
"))
        (beginning-of-buffer)
        (end-of-line))))
  
(add-hook 'ldraw-mode-hook 'ldraw-insert-headers)

(defun ldraw-make-syntax-table ()
  ""
  (make-local-variable 'ldraw-mode-syntax-table)
  (setq ldraw-mode-syntax-table (make-syntax-table))
  (set-syntax-table ldraw-mode-syntax-table)
  (modify-syntax-entry	?. "w" ldraw-mode-syntax-table)
  (modify-syntax-entry	?- "w" ldraw-mode-syntax-table))

(defun ldraw-mode ()
  "Major mode for editing LDraw DAT files.

Most command can be repeated over a number of lines, by prepending the
command with a prefix argument.  Here's an example:

Calling `ldraw-clean-line' with no prefix argument, i.e. \"C-c C-q\"
cleans the current line.  With an empty prefix argument (\"C-u C-c
C-q\"), it cleans all lines in the buffer.  A positive argument n (\"C-u
n C-c C-q\") means to clean the current line as well as the n-1 below.
Finally, calling the function with a negative argument -n (\"C-u - n C-c
C-q\") cleans the n lines above the cursor.

If you need to perform many functions over a specific region, I advice
you to use Emacs' built in `narrow-to-region' command, normally bound
to \"C-x n n\".  That way, you can narrow to the region you are
working on and perform translations or rotation on the region by using
the \"C-u\" prefix to the LDraw-mode commands.  When you're done,
simply widen the buffer back to normal (\"C-x n w\").

\\{ldraw-mode-map}
"
  (interactive)
  (kill-all-local-variables)
  (setq major-mode 'ldraw-mode)
  (setq mode-name "LDraw")
  ;;  (setq local-abbrev-table ldraw-mode-abbrev-table)
  (make-local-variable 'paragraph-start)
  (setq paragraph-start (concat "$\\|" page-delimiter))
  (ldraw-make-syntax-table)
  (make-local-variable 'paragraph-separate)
  (setq paragraph-separate paragraph-start)
  (make-local-variable 'paragraph-ignore-fill-prefix)
  (setq paragraph-ignore-fill-prefix t)
  ;;  (make-local-variable 'indent-line-function)
  ;;  (setq indent-line-function 'ldraw-indent-line)
  (make-local-variable 'require-final-newline)
  (setq require-final-newline t)
  (make-local-variable 'comment-start)
  (setq comment-start "^ *0 ")
  (make-local-variable 'comment-end)
  (setq comment-end "")
  (make-local-variable 'comment-column)
  (setq comment-column 0)
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip "^ *0 +")
  ;;  (make-local-variable 'comment-indent-function)
  ;;  (setq comment-indent-function 'ldraw-comment-indent)
  (make-local-variable 'parse-sexp-ignore-comments)
  (setq parse-sexp-ignore-comments t)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '(ldraw-font-lock-keywords))
  (use-local-map ldraw-mode-map)
  (run-hooks 'ldraw-mode-hook))

(defun ldraw-ledit-mode ()
  "Start up the LEdit emulator.

Note that this temporarily erases the global key map, so that you will
no longer be able to use Emacs as an editor.  Exit the emulator by
pressing \"/ f e\".

\\{ldraw-ledit-mode-map}
"
  (interactive)
  (use-local-map ldraw-ledit-mode-map)
  (setq mode-name "LDraw (LEdit)")
  (setq major-mode 'ldraw-ledit-mode)
  (message "Exit LEdit emulator with \"/ f e\".")
)

(defun ldraw-ledit-exit ()
  "Exit LEdit emulator."
  (interactive)
  (use-local-map ldraw-mode-map)
  (setq mode-name "LDraw")
  (setq major-mode 'ldraw-mode)
)

(provide 'ldraw-mode)
