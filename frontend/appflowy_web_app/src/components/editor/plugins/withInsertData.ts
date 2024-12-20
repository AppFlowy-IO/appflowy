import { CustomEditor } from '@/application/slate-yjs/command';
import { YjsEditor } from '@/application/slate-yjs';
import { findSlateEntryByBlockId, getBlockEntry } from '@/application/slate-yjs/utils/editor';
import { ReactEditor } from 'slate-react';
import { BlockType, FieldURLType, FileBlockData, ImageBlockData, ImageType } from '@/application/types';
import { MAX_IMAGE_SIZE } from '@/components/_shared/image-upload';
import { FileHandler } from '@/utils/file';
import { notify } from '@/components/_shared/notify';

export const withInsertData = (editor: ReactEditor) => {
  const { insertData } = editor;

  const e = editor as YjsEditor;

  editor.insertData = (data: DataTransfer) => {
    // Do something with the data...
    const fileArray = Array.from(data.files);
    const { selection } = editor;
    const blockId = getBlockEntry(e)[0].blockId;

    insertData(data);

    if (blockId && fileArray.length > 0 && selection) {
      void (async () => {
        let newBlockId: string | undefined = blockId;

        for (const file of fileArray) {
          if (file.size > MAX_IMAGE_SIZE) {
            notify.error('File size is too large, max size is 7MB');
            return;
          }

          const url = await e.uploadFile?.(file);
          let fileId = '';

          if (!url) {
            const fileHandler = new FileHandler();
            const res = await fileHandler.handleFileUpload(file);

            fileId = res.id;
          }

          const isImage = file.type.startsWith('image/');

          if (isImage) {
            const data = {
              url: url,
              image_type: ImageType.External,
            } as ImageBlockData;

            if (fileId) {
              data.retry_local_url = fileId;
            }

            // Handle images...
            newBlockId = CustomEditor.addBelowBlock(e, blockId, BlockType.ImageBlock, data);
          } else {
            const data = {
              url: url,
              name: file.name,
              uploaded_at: Date.now(),
              url_type: FieldURLType.Upload,
            } as FileBlockData;

            if (fileId) {
              data.retry_local_url = fileId;
            }

            // Handle files...
            newBlockId = CustomEditor.addBelowBlock(e, blockId, BlockType.FileBlock, data);
          }

        }

        if (newBlockId) {
          const id = CustomEditor.addBelowBlock(e, newBlockId, BlockType.Paragraph, {});

          if (!id) return;

          const [, path] = findSlateEntryByBlockId(e, id);

          editor.select(editor.start(path));
        }

      })();

    }
  };

  return editor;
};