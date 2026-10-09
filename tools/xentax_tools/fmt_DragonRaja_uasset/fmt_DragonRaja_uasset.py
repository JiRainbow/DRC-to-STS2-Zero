# Dragon Raja uasset importer/convertor by Bigchillghost

gPromptFailureMessage = False

import os

import rapi
from inc_noesis import *

def registerNoesisTypes():
	handle = noesis.register("Dragon Raja", ".uasset;.ubulk;.uexp")
	noesis.setHandlerTypeCheck(handle, noepyCheckType)
	noesis.setHandlerLoadModel(handle, noepyLoadModel)
	#noesis.logPopup()
	return 1

#check if it's this type based on the data
def noepyCheckType(data):
	if len(data) < 0x80:
		return 0
	bs = NoeBitStream(data)
	Magic = bs.readUInt()
	if Magic != 0x9E2A83C1:
		return 0
	return 1

def messagePrompt(str):
	if gPromptFailureMessage:
		noesis.messagePrompt(str)
	
#load the model
def noepyLoadModel(data, mdlList):
	bound = 0x20000
	if gPromptFailureMessage:
		noesis.logPopup()
	bs = NoeBitStream(data)
	bs.seek(0x18, NOESEEK_ABS)
	SrchOffset = bs.readInt()
	Len = bs.readInt()
	bs.seek(Len+4, NOESEEK_REL)
	stringNum = bs.readInt()
	stringBufStart = bs.readInt()
	bs.seek(0x78, NOESEEK_REL)
	EndMagicOffset = bs.readInt()
	TotalSize = bs.getSize()
	srcMode = 0
	if TotalSize < EndMagicOffset:
		srcMode = 1
	
	strTable = []
	bs.seek(stringBufStart, NOESEEK_ABS)
	for i in range(0, stringNum):
		Len = bs.readInt()
		strTable.append(noeStrFromBytes(bs.readBytes(Len), "UTF8"))
		bs.seek(4, NOESEEK_REL)
	
	contentType = -1
	while 1:
		bs.seek(0x10, NOESEEK_REL)
		if bs.readInt() >= 0:
			break
		typeID = bs.readInt()
		typeStr = strTable[typeID]
		if typeStr == "SkeletalMesh":
			contentType = 0
			break
		elif typeStr == "Skeleton":
			contentType = 0
			break
		elif typeStr == "Texture2D":
			contentType = 1
			break
		elif typeStr == "StaticMesh":
			contentType = 2
			break
		else:
			bs.seek(4, NOESEEK_REL)
	
	dataSrc = rapi.getInputName()
	if srcMode == 1:
		try:
			uexp = rapi.loadIntoByteArray(dataSrc.replace(".uasset", ".uexp"))
		except RuntimeError:
			messagePrompt("Error: missing corresponding uexp file!")
			return 0
		bs = NoeBitStream(uexp)
		SrchOffset = 0
		TotalSize = bs.getSize()
		
	bs.seek(SrchOffset, NOESEEK_ABS)
	BufSize = TotalSize - SrchOffset
	#if BufSize > bound:
	#	BufSize = bound
	TempBuf = bs.readBytes(BufSize)
	if contentType == 0:
		while 1:
			Offset = TempBuf.find(b"\xFF\xFF\xFF\xFF")
			if Offset == -1:
				return 0
			Offset += SrchOffset - 0xC
			bs.seek(Offset, NOESEEK_ABS)
			TestA = bs.readUInt()
			if TestA < 0x200:
				bs.seek(TestA*0xC, NOESEEK_REL)
				TestB = bs.readUInt()
			else:
				TestB = 0
			if TestA == TestB:
				bs.seek(Offset, NOESEEK_ABS)
				break
			else:
				SrchOffset = Offset + 0x10
				BufSize = TotalSize - SrchOffset
				if BufSize > bound:
					BufSize = bound
				bs.seek(SrchOffset, NOESEEK_ABS)
				TempBuf = bs.readBytes(BufSize)
		parseSkelMesh(bs, mdlList, strTable)
		rapi.setPreviewOption("setAngOfs", "0 180 0")
		return 1
	elif contentType == 1:
		Offset = TempBuf.find(b"\x00\x50\x46\x5F")
		if Offset == -1:
			return 0
		Offset += SrchOffset + 1
		bs.seek(Offset, NOESEEK_ABS)
		if srcMode == 1:
			dataOffset = EndMagicOffset - TotalSize - bs.getSize()
		else:
			dataOffset = EndMagicOffset
		parseTexture2D(bs, srcMode, dataOffset, dataSrc)
		return 0
	elif contentType == 2:
		Offset = TempBuf.find(b"\x00\x00\x01\x00\x01\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00")
		if Offset == -1:
			return 0
		Offset += SrchOffset + 0x20
		bs.seek(Offset, NOESEEK_ABS)
		parseStaticMesh(bs, mdlList)
		rapi.setPreviewOption("setAngOfs", "0 180 0")
		return 1
	else:
		return 0

def parseTexture2D(bs, srcMode, dataOffset, srcName):
	fmtStr = bs.readString()
	bs.seek(4, NOESEEK_REL)
	TexFile = NoeBitStream()
	TexFile.writeBytes(b"PVR\x03\x00\x00\x00\x00")
	if fmtStr == "PF_ASTC_6x6":
		TexFile.writeInt64(31)
	elif fmtStr == "PF_ETC2_RGB":
		TexFile.writeInt64(22)
	elif fmtStr == "PF_ETC2_RGBA":
		TexFile.writeInt64(23)
	else:
		TexFile.writeInt64(0x0)
	TexFile.writeInt64(0x0)
	
	curPos = bs.tell()
	bs.seek(8, NOESEEK_REL)
	Test = bs.readInt()
	noHeader = 0
	if Test == 0x48:
		noHeader = 1
	bs.seek(curPos, NOESEEK_ABS)
	if noHeader == 1:
		bs.seek(0xC, NOESEEK_REL)
		Size = bs.readInt()
		UnzipSize = bs.readInt()
		bs.seek(8, NOESEEK_REL)
		if Size != UnzipSize:
			return 0
		pixelData = bs.readBytes(Size)
		Width = bs.readInt()
		Height = bs.readInt()
	else:
		bs.seek(0xC, NOESEEK_REL)
		Size = bs.readInt()
		UnzipSize = bs.readInt()
		if Size != UnzipSize:
			return 0
		relOffset = bs.readInt64()
		Width = bs.readInt()
		Height = bs.readInt()
		if relOffset < 0:
			try:
				ubulk = rapi.loadIntoByteArray(srcName.replace(".uasset", ".ubulk"))
			except RuntimeError:
				messagePrompt("Error: missing corresponding ubulk file!")
				return 0
			bs = NoeBitStream(ubulk)
		else:
			bs.seek(dataOffset, NOESEEK_ABS)
		pixelData = bs.readBytes(Size)
	TexFile.writeInt(Height)
	TexFile.writeInt(Width)
	for i in range(0, 4):
		TexFile.writeInt(1)
	TexFile.writeInt(0)
	TexFile.writeBytes(pixelData)
	outName = srcName.replace(".uasset", ".pvr")
	outAbs = os.path.abspath(outName)
	baseDir = os.path.abspath(os.path.dirname(srcName) or os.curdir)
	if os.path.dirname(outAbs) != baseDir:
		raise ValueError("refusing to write outside the source directory: %s" % outName)
	Tex = open(outAbs, "wb")
	Tex.write(TexFile.getBuffer())
	Tex.close()
	return 1

def parseSkelMesh(bs, mdlList, strTable):
	# bone info
	boneCount = bs.readInt()
	boneNameIdx = []
	parentID = []
	for i in range(0, boneCount):
		boneNameIdx.append(bs.readInt())
		bs.seek(4, NOESEEK_REL)
		parentID.append(bs.readInt())
	bs.seek(4, NOESEEK_REL)
	bones = []
	for i in range(0, boneCount):
		Rot = NoeQuat.fromBytes(bs.readBytes(0x10))
		Tran = NoeVec3.fromBytes(bs.readBytes(0xC))
		Scaling = NoeVec3.fromBytes(bs.readBytes(0xC))
		boneMat = Rot.toMat43(1)
		boneMat[3] = Tran
		bones.append( NoeBone(i, strTable[boneNameIdx[i]], boneMat, None, parentID[i]) )#bonePIndex
	bs.seek(boneCount*0xC+4, NOESEEK_REL) # boneIDs
		
	# Converting local matrix to world space
	for i in range(0, boneCount):
		j = bones[i].parentIndex
		if j != -1:
			bones[i].setMatrix(bones[i].getMatrix()*bones[j].getMatrix())
			#j = bones[j].parentIndex'''
	
	
	# meshes
	meshes = []
	meshCount = bs.readInt()
	lodCount = bs.readInt()
	for i in range(0, meshCount):
		for j in range(0, lodCount):
			bs.seek(2, NOESEEK_REL)
			blockCount = bs.readInt()
			refIDArray = []
			blockVcount = []
			for k in range(0, blockCount):
				bs.seek(0x14, NOESEEK_REL)
				blockVcount.append(bs.readInt())
				bs.seek(4, NOESEEK_REL)
				refIDs = []
				Count = bs.readInt()
				if j > 0:
					bs.seek(Count*2, NOESEEK_REL)
				else:
					for L in range(0, Count):
						refIDs.append(bs.readShort())
					refIDArray.append(refIDs)
				bs.seek(0x1E, NOESEEK_REL)
				Count = bs.readInt()
				bs.seek(Count*4, NOESEEK_REL)
				Count = bs.readInt()
				bs.seek(Count*8, NOESEEK_REL)
				bs.seek(4, NOESEEK_REL)
			bs.seek(1, NOESEEK_REL)
			# polygon indices
			PolygonIndex = []
			EleSize = bs.readInt()
			FIcount = bs.readInt()
			if j > 0:
				bs.seek(FIcount*2, NOESEEK_REL)
			else:
				for k in range(0, FIcount):
					PolygonIndex.append(bs.readUShort())
			for k in range(0, 2):
				Count = bs.readInt()
				bs.seek(Count*2, NOESEEK_REL)
			bs.seek(0xC, NOESEEK_REL)
			Vcount = bs.readInt()
			Positions = []
			if j > 0:
				bs.seek(Vcount*0xC, NOESEEK_REL)
			else:
				for k in range(0, Vcount):
					Positions.append(NoeVec3.fromBytes(bs.readBytes(12)))
			bs.seek(0x1A, NOESEEK_REL)
			Normals = []
			if j > 0:
				bs.seek(Vcount*8, NOESEEK_REL)
			else:
				for k in range(0, Vcount):
					bs.seek(4, NOESEEK_REL)
					Normals.append(NoeVec3([bs.readByte()/127.5,bs.readByte()/127.5, bs.readByte()/127.5]))
					bs.seek(1, NOESEEK_REL)
			EleSize = bs.readInt()
			EleCount = bs.readInt()
			Offset = bs.tell() + EleCount*EleSize
			Skip = EleCount // Vcount
			Skip = (Skip-1)*4
			TexCoords = []
			if j == 0:
				for k in range(0, Vcount):
					TexCoords.append(NoeVec3([bs.readHalfFloat(),bs.readHalfFloat(), 0.0]))
					bs.seek(Skip, NOESEEK_REL)

				mesh = NoeMesh(PolygonIndex, Positions, "mesh%d"%i)
				mesh.setNormals(Normals)
				mesh.setUVs(TexCoords)
	
			bs.seek(Offset, NOESEEK_ABS)	
			hasWeight = bs.readShort()
			if hasWeight == 1:
				bs.seek(8, NOESEEK_REL)
				EleSize = bs.readInt()
				bs.seek(4, NOESEEK_REL)
				if j > 0:
					bs.seek(Vcount*EleSize, NOESEEK_REL)
				else:
					bonePerVert = EleSize // 2
					blockVcount.append(Vcount)
					for k in range(0, blockCount):
						blockVcount[k]= blockVcount[k+1] - blockVcount[k]
					for k in range(0, blockCount):
						for l in range(0, blockVcount[k]):
							idx = []
							boneIDs = []
							boneWeight = []
							for m in range(0, bonePerVert):
								idx.append(bs.readByte())
							for m in range(0, bonePerVert):
								weight = bs.readByte()
								if weight != 0:
									boneIDs.append((refIDArray[k])[idx[m]])
									boneWeight.append(weight/255.0)
							mesh.weights.append(NoeVertWeight(boneIDs, boneWeight))
					
			hasColor = bs.readShort()
			if hasColor == 1:
				bs.seek(0x10, NOESEEK_REL)
				bs.seek(Vcount*4, NOESEEK_REL) # color
			elif hasColor == 0x101:
				bs.seek(-2, NOESEEK_REL)
			if j == 0:
				meshes.append(mesh)
	
	if meshCount != 0:
		mdl = NoeModel(meshes)
	else:
		mdl = NoeModel()
	mdl.setBones(bones)
	mdlList.append(mdl)
	return 1

def parseStaticMesh(bs, mdlList):
	meshes = []
	skipCount = bs.readInt()
	bs.seek(skipCount*4, NOESEEK_REL)
	lodCount = bs.readInt()
	for i in range(0, lodCount):
		bs.seek(2, NOESEEK_REL)
		entryCount = bs.readInt()
		bs.seek(entryCount*0x1C+0x10, NOESEEK_REL)
		Vcount = bs.readInt()
		Positions = []
		for j in range(0, Vcount):
			Positions.append(NoeVec3.fromBytes(bs.readBytes(12)))
		bs.seek(0x16, NOESEEK_REL)
		NMcount = bs.readInt()
		Normals = []
		for j in range(0, NMcount):
			bs.seek(4, NOESEEK_REL)
			Normals.append(NoeVec3([bs.readByte()/127.5,bs.readByte()/127.5, bs.readByte()/127.5]))
			bs.seek(1, NOESEEK_REL)
		EleSize = bs.readInt()
		EleCount = bs.readInt()
		Offset = bs.tell() + EleCount*EleSize
		ChannelCnt = EleCount // Vcount
		TexCoords = []
		TexCoords2 = []
		if ChannelCnt == 2:
			for j in range(0, Vcount):
				TexCoords.append(NoeVec3([bs.readHalfFloat(),bs.readHalfFloat(), 0.0]))
				TexCoords2.append(NoeVec3([bs.readHalfFloat(),bs.readHalfFloat(), 0.0]))
		else:
			for j in range(0, Vcount):
				TexCoords.append(NoeVec3([bs.readHalfFloat(),bs.readHalfFloat(), 0.0]))
		
		bs.seek(Offset, NOESEEK_ABS)	
		hasColor = bs.readShort()
		if hasColor == 1:
			EleSize = bs.readInt()
			EleCount = bs.readInt()
			if EleCount > 0:
				bs.seek(Vcount*4+8, NOESEEK_REL) # color
		elif hasColor == 0x101:
			bs.seek(-2, NOESEEK_REL)
		
		# polygon indices
		for j in range(0, 4):
			bs.seek(8, NOESEEK_REL)
			EleSize = bs.readInt()
			if EleSize > 0:
				FIcount = EleSize // 2
				PolygonIndex = []
				for k in range(0, FIcount):
					PolygonIndex.append(bs.readUShort())
		
				if i == 0 and j == 0: # preserve the highest lod
					mesh = NoeMesh(PolygonIndex, Positions, "LOD%d_"%i+"Set%d"%j)
					mesh.setNormals(Normals)
					mesh.setUVs(TexCoords)
					if ChannelCnt == 2:
						mesh.setUVs(TexCoords2, 1)
					meshes.append(mesh)
		bs.seek(entryCount*0xC+0xC, NOESEEK_REL)
	mdl = NoeModel(meshes)
	mdlList.append(mdl)
	return 1