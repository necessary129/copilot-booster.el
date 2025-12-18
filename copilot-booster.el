;;; copilot-booster.el --- emacs-lsp-booster for copilot.el -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2025 Muhammed Shamil K
;; Based on https://github.com/jdtsmith/eglot-booster
;;
;; Author: noteness <noteness@riseup.net>
;; Maintainer: noteness <noteness@riseup.net>
;; Version: 0.0.1
;; Keywords: tools, convenience, copilot
;; Prefix: eglot-booster
;; Separator: -
;; Homepage: https://github.com/noteness/copilot-booster
;; Package-Requires: ((emacs "29.1") (copilot "0.1") (jsonrpc "1.0") (seq "2.24"))
;;
;; This file is not part of GNU Emacs.
;;
;; copilot-booster is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; copilot-booster is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; This small minor mode boosts copilot.el with emacs-lsp-booster.
;; It intercepts the Copilot server command and wraps it, enabling
;; bytecode translation for faster JSON parsing.
;; 
;;
;; Note: You may need to run M-x copilot-diagnose (which restarts the server)
;; after enabling this mode for changes to take effect.

;;; Code:
(require 'copilot)
(require 'jsonrpc)


(defcustom copilot-booster-no-remote-boost nil
  "If non-nil, do not boost remote hosts."
  :group 'copilot
  :type 'boolean)

(defcustom copilot-booster-io-only nil
  "If non-nil, do not translate JSON into bytecode.
I/O buffering is still performed."
  :group 'copilot
  :type 'boolean)

(defvar-local copilot-booster-boosted nil
  "Non-nil if the current process buffer is handled by emacs-lsp-booster.")

(defun copilot-booster--jsonrpc--json-read (orig-func)
  "Read JSON or bytecode, wrapping the ORIG-FUNC JSON reader.
This allows reading the bytecode format output by emacs-lsp-booster."
  (if copilot-booster-boosted ; local to process-buffer
      (or (and (= (following-char) ?#)
               (let ((bytecode (read (current-buffer))))
                 (when (byte-code-function-p bytecode)
                   (funcall bytecode))))
          (funcall orig-func))
    ;; Not in a boosted process, fallback
    (funcall orig-func)))

(defvar copilot-booster--boost
  '("emacs-lsp-booster" "--json-false-value" ":json-false" "--"))

(defvar copilot-booster--boost-io-only
  '("emacs-lsp-booster" "--disable-bytecode" "--"))

(defun copilot-booster--wrap-command (command)
  "Wrap the Copilot server COMMAND list with the booster executable.
Intended as :filter-return advice for `copilot--command'."
  (if (or (and copilot-booster-no-remote-boost (file-remote-p default-directory))
          (not (consp command)))
      command
    (let ((boost-args (if copilot-booster-io-only
                          copilot-booster--boost-io-only
                        copilot-booster--boost)))
      (append boost-args command))))

(defun copilot-booster--init (conn)
  "Register the COPILOT connection CONN as boosted if configured.
Intended as :filter-return advice for `copilot--make-connection'."
  (when-let ((proc (jsonrpc--process conn))
             (com (process-command proc))
             (buf (process-buffer proc)))
    ;; Check if the running command actually includes the booster
    (when (seq-find (lambda (s) (string-match-p "emacs-lsp-booster" s)) com)
      (with-current-buffer buf
        (setq copilot-booster-boosted t)
        (copilot--log 'info "Copilot server is boosted via emacs-lsp-booster."))))
  conn)

;;;###autoload
(define-minor-mode copilot-booster-mode
  "Minor mode which boosts Copilot with emacs-lsp-booster.
The emacs-lsp-booster program must be compiled and available on
variable `exec-path'.

Toggling this mode ON adds advice to `copilot.el' functions.
Toggling OFF removes them.
Note: You must restart the Copilot server (M-x copilot-diagnose)
after toggling this mode."
  :global t
  :group 'copilot
  (cond
   (copilot-booster-mode
    (unless (executable-find "emacs-lsp-booster")
      (setq copilot-booster-mode nil)
      (user-error "The emacs-lsp-booster program is not installed"))
    
    (unless copilot-booster-io-only
      (advice-add 'jsonrpc--json-read :around #'copilot-booster--jsonrpc--json-read))
    
    (advice-add 'copilot--command :filter-return #'copilot-booster--wrap-command)
    
    (advice-add 'copilot--make-connection :filter-return #'copilot-booster--init))
   
   (t
    ;; Remove all advice
    (advice-remove 'jsonrpc--json-read #'copilot-booster--jsonrpc--json-read)
    (advice-remove 'copilot--command #'copilot-booster--wrap-command)
    (advice-remove 'copilot--make-connection #'copilot-booster--init))))

(provide 'copilot-booster)
;;; copilot-booster.el ends here
