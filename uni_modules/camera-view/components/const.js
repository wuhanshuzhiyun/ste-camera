export const TEXT_UID = "scan-mode-text";

export const viewText = (screenHeight, text = '请对准条码，自动识别') => ({
	uid: TEXT_UID,
	type: 'text',
	text,
	style: {
		top: screenHeight - 150,
		fontColor: '#FFFFFF',
		fontWeight: 'bold',
		textAlign: 'center',
		fontSize: 18
	}
})

export const views = (screenWidth, screenHeight) => [
	viewText(screenHeight),
	{
		type: 'image',
		image: 'https://image.whzb.com/chain/inte-mall/00-普通图片/00-开发版/通用/扫码方框.png?202507100',
		style: {
			width: screenWidth - 30,
			height: screenHeight - 240,
			left: 15,
			top: 60
		}
	}
]
export const scanBar = (screenHeight) => ({
	image: 'https://image.whzb.com/chain/inte-mall/00-普通图片/00-开发版/通用/扫码图片.png?202507100',
	widthPercent: 90,
	startY: 30,
	endY: screenHeight - 240
})