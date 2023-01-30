import './App.css';
import {
  UserEventSignIn,
  SignInPayloadPB,
  UserEventGetUserProfile,
  UserEventGetUserSetting,
} from '../../../services/backend/events/flowy-user/index';
import { nanoid } from 'nanoid';
import { UserNotificationListener } from '../user/application/notifications';
import {
  ColorStylePB,
  CreateAppPayloadPB,
  CreateWorkspacePayloadPB,
  FolderEventCreateApp,
  FolderEventCreateView,
  FolderEventCreateWorkspace,
  FolderEventOpenWorkspace,
  FolderEventReadCurrentWorkspace,
  WorkspaceIdPB,
} from '../../../services/backend/events/flowy-folder';
import { useEffect, useState } from 'react';
import * as dependency_1 from '../../../services/backend/classes/flowy-folder/app';

const TestApiButton = () => {
  const [workspaceId, setWorkspaceId] = useState('');
  const [appId, setAppId] = useState('');

  useEffect(() => {
    if (!workspaceId?.length) return;
    (async () => {
      const openWorkspaceResult = await FolderEventOpenWorkspace(
        WorkspaceIdPB.fromObject({
          value: workspaceId,
        })
      );

      if (openWorkspaceResult.ok) {
        const pb = openWorkspaceResult.val;
        console.log(pb.toObject());
      } else {
        throw new Error('open workspace error');
      }

      const createAppResult = await FolderEventCreateApp(
        CreateAppPayloadPB.fromObject({
          name: 'APP_1',
          desc: 'Application One',
          color_style: ColorStylePB.fromObject({ theme_color: 'light' }),
          workspace_id: workspaceId,
        })
      );
      if (createAppResult.ok) {
        const pb = createAppResult.val;
        const obj = pb.toObject();
        console.log(obj);
      } else {
        throw new Error('create app error');
      }
    })();
  }, [workspaceId]);

  async function sendSignInEvent() {
    let make_payload = () =>
      SignInPayloadPB.fromObject({
        email: nanoid(4) + '@gmail.com',
        password: 'A!@123abc',
        name: 'abc',
      });

    let listener = await new UserNotificationListener({
      onUserSignIn: (userProfile) => {
        console.log(userProfile);
      },
      onProfileUpdate(userProfile) {
        console.log(userProfile);
        // stop listening the changes
        listener.stop();
      },
    });

    await listener.start();

    const signInResult = await UserEventSignIn(make_payload());
    if (signInResult.ok) {
      const pb = signInResult.val;
      console.log(pb.toObject());
    } else {
      throw new Error('sign in error');
    }

    const getSettingsResult = await UserEventGetUserSetting();
    if (getSettingsResult.ok) {
      const pb = getSettingsResult.val;
      console.log(pb.toObject());
    } else {
      throw new Error('get user settings error');
    }

    const createWorkspaceResult = await FolderEventCreateWorkspace(
      CreateWorkspacePayloadPB.fromObject({
        name: 'WS_1',
        desc: 'Workspace One',
      })
    );

    if (createWorkspaceResult.ok) {
      const pb = createWorkspaceResult.val;
      console.log(pb.toObject());
      const workspace: {
        id?: string;
        name?: string;
        desc?: string;
        apps?: ReturnType<typeof dependency_1.RepeatedAppPB.prototype.toObject>;
        modified_time?: number;
        create_time?: number;
      } = pb.toObject();
      setWorkspaceId(workspace?.id || '');
    } else {
      throw new Error('create workspace error');
    }

    /**/
  }

  return (
    <div className='text-white bg-gray-500 h-screen flex flex-col justify-center items-center gap-4'>
      <h1 className='text-3xl'>Welcome to AppFlowy!</h1>

      <div>
        <button className='bg-gray-700 p-4 rounded-md' type='button' onClick={() => sendSignInEvent()}>
          Sign in and create sample data
        </button>
      </div>
    </div>
  );
};

export default TestApiButton;
