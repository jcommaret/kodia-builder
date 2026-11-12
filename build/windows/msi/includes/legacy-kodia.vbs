' Kodia: up to 2.6.x, Kodia's MSI had the UpgradeCode that VSCodium's and Void's still have. FindRelatedProducts
' puts every product under it in LEGACYKODIAFOUND; this keeps only Kodia's, named like "Kodia 1.141.0 (x64)"
' (LEGACYKODIAPRODUCTNAME, then a space and the version), for RemoveExistingProducts to remove.
' A product whose name can't be read is kept installed.
Function KeepOnlyLegacyKodia()
	Dim prefix, kept, code, name
	prefix = Session.Property("LEGACYKODIAPRODUCTNAME") & " "
	kept = ""
	For Each code In Split(Session.Property("LEGACYKODIAFOUND"), ";")
		If code <> "" Then
			name = ""
			On Error Resume Next
			name = Session.Installer.ProductInfo(code, "ProductName")
			On Error GoTo 0
			If Left(name, Len(prefix)) = prefix And IsNumeric(Mid(name, Len(prefix) + 1, 1)) Then
				If kept <> "" Then kept = kept & ";"
				kept = kept & code
			End If
		End If
	Next
	Session.Property("LEGACYKODIAFOUND") = kept
	KeepOnlyLegacyKodia = 1
End Function
